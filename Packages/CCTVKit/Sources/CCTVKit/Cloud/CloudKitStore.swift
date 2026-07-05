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
                CKSchema.Chunk.byteCount
            ]
        )

        return try response.compactMap { _, result in
            try makeVideoChunk(from: result.get())
        }
        .sorted { $0.index < $1.index }
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
        let query = CKQuery(recordType: CKSchema.RecordType.session, predicate: NSPredicate(value: true))
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
        let query = CKQuery(recordType: CKSchema.RecordType.chunk, predicate: NSPredicate(value: true))
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

    private func apply(_ session: SurveillanceSession, to record: CKRecord) {
        record[CKSchema.Session.startedAt] = session.startedAt as CKRecordValue
        record[CKSchema.Session.endedAt] = session.endedAt as CKRecordValue?
        record[CKSchema.Session.deviceName] = session.deviceName as CKRecordValue
        record[CKSchema.Session.status] = session.status.rawValue as CKRecordValue
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
            duration: duration
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
