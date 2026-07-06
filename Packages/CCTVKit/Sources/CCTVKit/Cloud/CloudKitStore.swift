import CloudKit
import Foundation

public enum CloudKitStoreError: Error, Equatable, LocalizedError {
    case malformedRecord(String)

    public var errorDescription: String? {
        switch self {
        case let .malformedRecord(recordName):
            "CloudKit record is missing required fields: \(recordName)"
        }
    }
}

public final class CloudKitStore: @unchecked Sendable {
    public static let m0SharedProbeRecordName = "m0-shared-probe"

    private static let retentionQueryUpperBound = Date(timeIntervalSince1970: 4_102_444_800)

    private let container: CKContainer
    private let database: CKDatabase

    public init(containerIdentifier: String = CKSchema.containerIdentifier) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
    }

    public func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    @discardableResult
    public func saveTestProbe(source: ProbeSource, message: String, deviceName: String) async throws -> CloudKitProbe {
        let probe = CloudKitProbe(source: source, message: message, deviceName: deviceName)
        let savedRecord = try await database.save(probe.makeRecord())
        return try CloudKitProbe(record: savedRecord)
    }

    @discardableResult
    public func saveM0SharedProbe(source: ProbeSource, deviceName: String) async throws -> CloudKitProbe {
        let probe = CloudKitProbe(
            id: Self.m0SharedProbeRecordName,
            source: source,
            message: "M0 private database cross-device verification",
            deviceName: deviceName
        )

        let record: CKRecord
        do {
            record = try await database.record(
                for: CKRecord.ID(recordName: Self.m0SharedProbeRecordName)
            )
            probe.applyFields(to: record)
        } catch let error as CKError where error.code == .unknownItem {
            record = probe.makeRecord()
        }

        let savedRecord = try await database.save(record)
        return try CloudKitProbe(record: savedRecord)
    }

    public func fetchM0SharedProbe() async throws -> CloudKitProbe {
        let record = try await database.record(
            for: CKRecord.ID(recordName: Self.m0SharedProbeRecordName)
        )
        return try CloudKitProbe(record: record)
    }

    public func fetchLatestTestProbe() async throws -> CloudKitProbe? {
        let query = CKQuery(
            recordType: CKSchema.RecordType.testProbe,
            predicate: NSPredicate(value: true)
        )

        let response = try await database.records(
            matching: query,
            desiredKeys: [
                CKSchema.TestProbe.source,
                CKSchema.TestProbe.message,
                CKSchema.TestProbe.createdAt,
                CKSchema.TestProbe.deviceName
            ],
            resultsLimit: 50
        )

        return try response.matchResults.compactMap { result in
            try CloudKitProbe(record: result.1.get())
        }
        .max { first, second in
            first.createdAt < second.createdAt
        }
    }

    @discardableResult
    public func saveSession(_ session: SurveillanceSession) async throws -> SurveillanceSession {
        let recordID = CKRecord.ID(recordName: session.id)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CKSchema.RecordType.session, recordID: recordID)
        }

        apply(session, to: record)
        let savedRecord = try await database.save(record)
        return try makeSession(from: savedRecord)
    }

    @discardableResult
    public func saveChunk(_ chunk: PendingChunkUpload, uploadedAt: Date = Date()) async throws -> VideoChunk {
        let recordID = CKRecord.ID(recordName: chunk.id)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CKSchema.RecordType.chunk, recordID: recordID)
        }

        let sessionRecordID = CKRecord.ID(recordName: chunk.sessionID)
        record[CKSchema.Chunk.session] = CKRecord.Reference(recordID: sessionRecordID, action: .deleteSelf)
        record[CKSchema.Chunk.index] = Int64(chunk.index) as CKRecordValue
        record[CKSchema.Chunk.startedAt] = chunk.startedAt as CKRecordValue
        record[CKSchema.Chunk.duration] = chunk.duration as CKRecordValue
        record[CKSchema.Chunk.byteCount] = chunk.byteCount as CKRecordValue
        record[CKSchema.Chunk.uploadedAt] = uploadedAt as CKRecordValue
        record[CKSchema.Chunk.video] = CKAsset(fileURL: chunk.fileURL)

        let savedRecord = try await database.save(record)
        return try makeVideoChunk(from: savedRecord)
    }

    public func fetchSession(id: String) async throws -> SurveillanceSession {
        let record = try await database.record(for: CKRecord.ID(recordName: id))
        return try makeSession(from: record)
    }

    public func fetchChunks(ids: [String]) async throws -> [VideoChunk] {
        let recordIDs = ids.map { CKRecord.ID(recordName: $0) }
        let response = try await database.records(
            for: recordIDs,
            desiredKeys: [
                CKSchema.Chunk.session,
                CKSchema.Chunk.index,
                CKSchema.Chunk.startedAt,
                CKSchema.Chunk.duration,
                CKSchema.Chunk.byteCount,
                CKSchema.Chunk.video
            ]
        )

        return try response.compactMap { _, result in
            try makeVideoChunk(from: result.get())
        }
        .sorted { $0.index < $1.index }
    }

    public func fetchSessions(limit: Int = 100) async throws -> [SurveillanceSession] {
        let query = CKQuery(
            recordType: CKSchema.RecordType.session,
            predicate: NSPredicate(
                format: "%K <= %@",
                CKSchema.Session.startedAt,
                Self.retentionQueryUpperBound as NSDate
            )
        )
        let response = try await database.records(
            matching: query,
            desiredKeys: [
                CKSchema.Session.startedAt,
                CKSchema.Session.endedAt,
                CKSchema.Session.deviceName,
                CKSchema.Session.status
            ],
            resultsLimit: limit
        )

        return try response.matchResults.compactMap { _, result in
            try makeSession(from: result.get())
        }
        .sorted { first, second in
            first.startedAt > second.startedAt
        }
    }

    public func fetchChunks(sessionID: String, limit: Int = 600) async throws -> [VideoChunk] {
        do {
            return try await fetchChunksBySessionReference(sessionID: sessionID, limit: limit)
        } catch where shouldFallbackFromSessionReferenceQuery(error) {
            return try await fetchChunksByStartedAt(limit: limit).filter { chunk in
                chunk.sessionID == sessionID
            }
        }
    }

    public func deleteSession(id: String) async throws {
        let chunks = try await fetchChunks(sessionID: id, limit: 2_000)
        for chunk in chunks {
            _ = try? await database.deleteRecord(withID: CKRecord.ID(recordName: chunk.id))
        }
        _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: id))
    }

    @discardableResult
    public func saveEvent(_ event: SecurityEvent) async throws -> SecurityEvent {
        let recordID = CKRecord.ID(recordName: event.id)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CKSchema.RecordType.event, recordID: recordID)
        }

        apply(event, to: record)
        let savedRecord = try await database.save(record)
        return try makeSecurityEvent(from: savedRecord)
    }

    public func fetchEvents(sessionID: String, after: Date? = nil, limit: Int = 200) async throws -> [SecurityEvent] {
        do {
            return try await fetchEventsBySessionReference(sessionID: sessionID, after: after, limit: limit)
        } catch where shouldFallbackFromSessionReferenceQuery(error) {
            return try await fetchEventsBroad(after: after, limit: limit).filter { event in
                event.sessionID == sessionID
            }
        }
    }

    public func fetchEvent(id: String) async throws -> SecurityEvent {
        let record = try await database.record(for: CKRecord.ID(recordName: id))
        return try makeSecurityEvent(from: record)
    }

    public func ensureEventSubscription(subscriptionID: String = "event-created-v1") async throws {
        let subscription = CKQuerySubscription(
            recordType: CKSchema.RecordType.event,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.title = "Mac CCTV"
        notificationInfo.alertLocalizationKey = "event_notification_body_format"
        notificationInfo.alertLocalizationArgs = [CKSchema.Event.type]
        notificationInfo.soundName = "default"
        notificationInfo.shouldBadge = true
        notificationInfo.desiredKeys = [
            CKSchema.Event.session,
            CKSchema.Event.type,
            CKSchema.Event.occurredAt
        ]
        subscription.notificationInfo = notificationInfo
        _ = try await database.save(subscription)
    }

    public func ensureEscalationSubscription(subscriptionID: String = "escalation-created-v1") async throws {
        let subscription = CKQuerySubscription(
            recordType: CKSchema.RecordType.event,
            predicate: NSPredicate(format: "%K == %@", CKSchema.Event.type, SecurityEventType.sirenEscalation.rawValue),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.title = "Mac CCTV"
        notificationInfo.alertLocalizationKey = "escalation_notification_body"
        notificationInfo.soundName = "default"
        notificationInfo.shouldBadge = true
        notificationInfo.category = "SIREN_ESCALATION"
        notificationInfo.desiredKeys = [
            CKSchema.Event.session,
            CKSchema.Event.type,
            CKSchema.Event.occurredAt
        ]
        subscription.notificationInfo = notificationInfo
        _ = try await database.save(subscription)
    }

    @discardableResult
    public func saveSignal(_ message: SignalMessage) async throws -> SignalMessage {
        let recordID = CKRecord.ID(recordName: message.id)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CKSchema.RecordType.signal, recordID: recordID)
        }

        apply(message, to: record)
        let savedRecord = try await database.save(record)
        return try makeSignalMessage(from: savedRecord)
    }

    public func fetchSignals(sessionID: String, after: Date? = nil, limit: Int = 200) async throws -> [SignalMessage] {
        do {
            return try await fetchSignalsBySessionReference(sessionID: sessionID, after: after, limit: limit)
        } catch where shouldFallbackFromSessionReferenceQuery(error) {
            return try await fetchSignalsBroad(after: after, limit: limit).filter { message in
                message.sessionID == sessionID
            }
        }
    }

    public func ensureSignalSubscription(subscriptionID: String = "signal-created-v1") async throws {
        let subscription = CKQuerySubscription(
            recordType: CKSchema.RecordType.signal,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.desiredKeys = [
            CKSchema.Signal.session,
            CKSchema.Signal.kind,
            CKSchema.Signal.sender,
            CKSchema.Signal.createdAt
        ]
        subscription.notificationInfo = notificationInfo
        _ = try await database.save(subscription)
    }

    public func fetchRetentionSnapshot(limit: Int = 200) async throws -> (sessions: [RetentionSession], chunks: [RetentionChunk]) {
        let sessions = try await fetchRetentionSessions(limit: limit)
        let chunks = try await fetchRetentionChunks(limit: limit)
        return (sessions, chunks)
    }

    public func sweepExpired(now: Date = Date(), policy: RetentionPolicy = RetentionPolicy()) async throws -> RetentionPlan {
        let snapshot = try await fetchRetentionSnapshot()
        let plan = policy.plan(sessions: snapshot.sessions, chunks: snapshot.chunks, now: now)

        for chunk in plan.chunksToDelete {
            _ = try? await database.deleteRecord(withID: CKRecord.ID(recordName: chunk.id))
        }
        for session in plan.sessionsToDelete {
            _ = try? await database.deleteRecord(withID: CKRecord.ID(recordName: session.id))
        }

        return plan
    }

    private func fetchRetentionSessions(limit: Int) async throws -> [RetentionSession] {
        let query = CKQuery(
            recordType: CKSchema.RecordType.session,
            predicate: NSPredicate(
                format: "%K <= %@",
                CKSchema.Session.startedAt,
                Self.retentionQueryUpperBound as NSDate
            )
        )
        let response = try await database.records(
            matching: query,
            desiredKeys: [
                CKSchema.Session.startedAt,
                CKSchema.Session.endedAt,
                CKSchema.Session.status
            ],
            resultsLimit: limit
        )

        return try response.matchResults.compactMap { _, result in
            let record = try result.get()
            return try makeRetentionSession(from: record)
        }
    }

    private func fetchRetentionChunks(limit: Int) async throws -> [RetentionChunk] {
        let query = CKQuery(
            recordType: CKSchema.RecordType.chunk,
            predicate: NSPredicate(
                format: "%K <= %@",
                CKSchema.Chunk.startedAt,
                Self.retentionQueryUpperBound as NSDate
            )
        )
        let response = try await database.records(
            matching: query,
            desiredKeys: [
                CKSchema.Chunk.session,
                CKSchema.Chunk.startedAt
            ],
            resultsLimit: limit
        )

        return try response.matchResults.compactMap { _, result in
            let record = try result.get()
            return try makeRetentionChunk(from: record)
        }
    }

    private func fetchChunksBySessionReference(sessionID: String, limit: Int) async throws -> [VideoChunk] {
        let sessionReference = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: sessionID),
            action: .none
        )
        let query = CKQuery(
            recordType: CKSchema.RecordType.chunk,
            predicate: NSPredicate(
                format: "%K == %@",
                CKSchema.Chunk.session,
                sessionReference
            )
        )
        let response = try await database.records(
            matching: query,
            desiredKeys: chunkPlaybackDesiredKeys,
            resultsLimit: limit
        )

        return try response.matchResults.compactMap { _, result in
            try makeVideoChunk(from: result.get())
        }
        .sorted { $0.index < $1.index }
    }

    private func fetchChunksByStartedAt(limit: Int) async throws -> [VideoChunk] {
        let query = CKQuery(
            recordType: CKSchema.RecordType.chunk,
            predicate: NSPredicate(
                format: "%K <= %@",
                CKSchema.Chunk.startedAt,
                Self.retentionQueryUpperBound as NSDate
            )
        )
        let response = try await database.records(
            matching: query,
            desiredKeys: chunkPlaybackDesiredKeys,
            resultsLimit: limit
        )

        return try response.matchResults.compactMap { _, result in
            try makeVideoChunk(from: result.get())
        }
        .sorted { $0.index < $1.index }
    }

    private func fetchEventsBySessionReference(sessionID: String, after: Date?, limit: Int) async throws -> [SecurityEvent] {
        let sessionReference = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: sessionID),
            action: .none
        )
        let query = CKQuery(
            recordType: CKSchema.RecordType.event,
            predicate: NSPredicate(
                format: "%K == %@",
                CKSchema.Event.session,
                sessionReference
            )
        )
        let response = try await database.records(
            matching: query,
            desiredKeys: eventDesiredKeys,
            resultsLimit: limit
        )

        return try response.matchResults.compactMap { _, result in
            try makeSecurityEvent(from: result.get())
        }
        .filter { event in
            guard let after else {
                return true
            }
            return event.occurredAt > after
        }
        .sorted { first, second in
            first.occurredAt < second.occurredAt
        }
    }

    private func fetchEventsBroad(after: Date?, limit: Int) async throws -> [SecurityEvent] {
        let query = CKQuery(
            recordType: CKSchema.RecordType.event,
            predicate: NSPredicate(value: true)
        )
        let response = try await database.records(
            matching: query,
            desiredKeys: eventDesiredKeys,
            resultsLimit: limit
        )

        return try response.matchResults.compactMap { _, result in
            try makeSecurityEvent(from: result.get())
        }
        .filter { event in
            guard let after else {
                return true
            }
            return event.occurredAt > after
        }
        .sorted { first, second in
            first.occurredAt < second.occurredAt
        }
    }

    private func fetchSignalsBySessionReference(sessionID: String, after: Date?, limit: Int) async throws -> [SignalMessage] {
        let sessionReference = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: sessionID),
            action: .none
        )
        let query = CKQuery(
            recordType: CKSchema.RecordType.signal,
            predicate: NSPredicate(
                format: "%K == %@",
                CKSchema.Signal.session,
                sessionReference
            )
        )
        let records = try await fetchAllMatches(query: query, desiredKeys: signalDesiredKeys, resultsLimit: limit)

        return try records.map { try makeSignalMessage(from: $0) }
        .filter { message in
            guard let after else {
                return true
            }
            return message.createdAt > after
        }
        .sorted { first, second in
            first.createdAt < second.createdAt
        }
    }

    private func fetchSignalsBroad(after: Date?, limit: Int) async throws -> [SignalMessage] {
        let query = CKQuery(
            recordType: CKSchema.RecordType.signal,
            predicate: NSPredicate(value: true)
        )
        let records = try await fetchAllMatches(query: query, desiredKeys: signalDesiredKeys, resultsLimit: limit)

        return try records.map { try makeSignalMessage(from: $0) }
        .filter { message in
            guard let after else {
                return true
            }
            return message.createdAt > after
        }
        .sorted { first, second in
            first.createdAt < second.createdAt
        }
    }

    /// `CKDatabase.records(matching:)` only returns a single server-decided page of
    /// results — a large `resultsLimit` does NOT guarantee everything comes back in
    /// one call. Callers here filter `after: date` in memory once the page is fetched,
    /// so an un-paginated fetch can silently drop records newer than whatever the
    /// server happened to include in that first page (e.g. long-lived sessions that
    /// accumulate many WebRTC signal records across repeated connect attempts). Follow
    /// `queryCursor` until exhausted so no matching record is ever dropped.
    private func fetchAllMatches(
        query: CKQuery,
        desiredKeys: [String]?,
        resultsLimit: Int
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var response = try await database.records(
            matching: query,
            desiredKeys: desiredKeys,
            resultsLimit: resultsLimit
        )
        records.append(contentsOf: try response.matchResults.map { try $0.1.get() })

        while let cursor = response.queryCursor {
            response = try await database.records(
                continuingMatchFrom: cursor,
                desiredKeys: desiredKeys,
                resultsLimit: resultsLimit
            )
            records.append(contentsOf: try response.matchResults.map { try $0.1.get() })
        }

        return records
    }

    private var chunkPlaybackDesiredKeys: [String] {
        [
            CKSchema.Chunk.session,
            CKSchema.Chunk.index,
            CKSchema.Chunk.startedAt,
            CKSchema.Chunk.duration,
            CKSchema.Chunk.byteCount,
            CKSchema.Chunk.video
        ]
    }

    private var eventDesiredKeys: [String] {
        [
            CKSchema.Event.session,
            CKSchema.Event.type,
            CKSchema.Event.occurredAt,
            CKSchema.Event.confidence
        ]
    }

    private var signalDesiredKeys: [String] {
        [
            CKSchema.Signal.session,
            CKSchema.Signal.kind,
            CKSchema.Signal.payload,
            CKSchema.Signal.sender,
            CKSchema.Signal.createdAt
        ]
    }

    private func shouldFallbackFromSessionReferenceQuery(_ error: Error) -> Bool {
        if let cloudKitError = error as? CKError, cloudKitError.code == .invalidArguments {
            return true
        }

        let description = (error as NSError).localizedDescription.lowercased()
        return description.contains("not marked queryable") || description.contains("queryable")
    }

    private func apply(_ session: SurveillanceSession, to record: CKRecord) {
        record[CKSchema.Session.startedAt] = session.startedAt as CKRecordValue
        record[CKSchema.Session.endedAt] = session.endedAt as CKRecordValue?
        record[CKSchema.Session.deviceName] = session.deviceName as CKRecordValue
        record[CKSchema.Session.status] = session.status.rawValue as CKRecordValue
    }

    private func apply(_ event: SecurityEvent, to record: CKRecord) {
        let sessionRecordID = CKRecord.ID(recordName: event.sessionID)
        record[CKSchema.Event.session] = CKRecord.Reference(recordID: sessionRecordID, action: .deleteSelf)
        record[CKSchema.Event.type] = event.type.rawValue as CKRecordValue
        record[CKSchema.Event.occurredAt] = event.occurredAt as CKRecordValue
        record[CKSchema.Event.confidence] = event.confidence as CKRecordValue
    }

    private func apply(_ message: SignalMessage, to record: CKRecord) {
        let sessionRecordID = CKRecord.ID(recordName: message.sessionID)
        record[CKSchema.Signal.session] = CKRecord.Reference(recordID: sessionRecordID, action: .deleteSelf)
        record[CKSchema.Signal.kind] = message.kind.rawValue as CKRecordValue
        record[CKSchema.Signal.payload] = message.payload as CKRecordValue
        record[CKSchema.Signal.sender] = message.sender.rawValue as CKRecordValue
        record[CKSchema.Signal.createdAt] = message.createdAt as CKRecordValue
    }

    private func makeSession(from record: CKRecord) throws -> SurveillanceSession {
        guard
            let startedAt = record[CKSchema.Session.startedAt] as? Date,
            let deviceName = record[CKSchema.Session.deviceName] as? String,
            let statusRaw = record[CKSchema.Session.status] as? String,
            let status = SessionStatus(rawValue: statusRaw)
        else {
            throw CloudKitStoreError.malformedRecord(record.recordID.recordName)
        }

        return SurveillanceSession(
            id: record.recordID.recordName,
            startedAt: startedAt,
            endedAt: record[CKSchema.Session.endedAt] as? Date,
            deviceName: deviceName,
            status: status
        )
    }

    private func makeVideoChunk(from record: CKRecord) throws -> VideoChunk {
        guard
            let sessionReference = record[CKSchema.Chunk.session] as? CKRecord.Reference,
            let indexValue = record[CKSchema.Chunk.index] as? Int64,
            let startedAt = record[CKSchema.Chunk.startedAt] as? Date,
            let duration = record[CKSchema.Chunk.duration] as? Double
        else {
            throw CloudKitStoreError.malformedRecord(record.recordID.recordName)
        }

        return VideoChunk(
            id: record.recordID.recordName,
            sessionID: sessionReference.recordID.recordName,
            index: Int(indexValue),
            startedAt: startedAt,
            duration: duration,
            assetFileURL: ChunkAssetCache.shared.stableFileURL(
                chunkID: record.recordID.recordName,
                sourceURL: (record[CKSchema.Chunk.video] as? CKAsset)?.fileURL
            ),
            byteCount: record[CKSchema.Chunk.byteCount] as? Int64 ?? 0
        )
    }

    private func makeSecurityEvent(from record: CKRecord) throws -> SecurityEvent {
        guard
            let sessionReference = record[CKSchema.Event.session] as? CKRecord.Reference,
            let typeRaw = record[CKSchema.Event.type] as? String,
            let type = SecurityEventType(rawValue: typeRaw),
            let occurredAt = record[CKSchema.Event.occurredAt] as? Date,
            let confidence = record[CKSchema.Event.confidence] as? Double
        else {
            throw CloudKitStoreError.malformedRecord(record.recordID.recordName)
        }

        return SecurityEvent(
            id: record.recordID.recordName,
            sessionID: sessionReference.recordID.recordName,
            type: type,
            occurredAt: occurredAt,
            confidence: confidence
        )
    }

    private func makeSignalMessage(from record: CKRecord) throws -> SignalMessage {
        guard
            let sessionReference = record[CKSchema.Signal.session] as? CKRecord.Reference,
            let kindRaw = record[CKSchema.Signal.kind] as? String,
            let kind = SignalKind(rawValue: kindRaw),
            let payload = record[CKSchema.Signal.payload] as? String,
            let senderRaw = record[CKSchema.Signal.sender] as? String,
            let sender = SignalSender(rawValue: senderRaw),
            let createdAt = record[CKSchema.Signal.createdAt] as? Date
        else {
            throw CloudKitStoreError.malformedRecord(record.recordID.recordName)
        }

        return SignalMessage(
            id: record.recordID.recordName,
            sessionID: sessionReference.recordID.recordName,
            kind: kind,
            payload: payload,
            sender: sender,
            createdAt: createdAt
        )
    }

    private func makeRetentionSession(from record: CKRecord) throws -> RetentionSession {
        guard
            let startedAt = record[CKSchema.Session.startedAt] as? Date,
            let statusRaw = record[CKSchema.Session.status] as? String,
            let status = SessionStatus(rawValue: statusRaw)
        else {
            throw CloudKitStoreError.malformedRecord(record.recordID.recordName)
        }

        return RetentionSession(
            id: record.recordID.recordName,
            startedAt: startedAt,
            endedAt: record[CKSchema.Session.endedAt] as? Date,
            status: status
        )
    }

    private func makeRetentionChunk(from record: CKRecord) throws -> RetentionChunk {
        guard
            let sessionReference = record[CKSchema.Chunk.session] as? CKRecord.Reference,
            let startedAt = record[CKSchema.Chunk.startedAt] as? Date
        else {
            throw CloudKitStoreError.malformedRecord(record.recordID.recordName)
        }

        return RetentionChunk(
            id: record.recordID.recordName,
            sessionID: sessionReference.recordID.recordName,
            startedAt: startedAt
        )
    }
}
