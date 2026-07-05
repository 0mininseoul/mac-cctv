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

public final class CloudKitStore {
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
}
