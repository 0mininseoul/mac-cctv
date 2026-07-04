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

    public func fetchLatestTestProbe() async throws -> CloudKitProbe? {
        let query = CKQuery(
            recordType: CKSchema.RecordType.testProbe,
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: CKSchema.TestProbe.createdAt, ascending: false)
        ]

        let response = try await database.records(
            matching: query,
            desiredKeys: [
                CKSchema.TestProbe.source,
                CKSchema.TestProbe.message,
                CKSchema.TestProbe.createdAt,
                CKSchema.TestProbe.deviceName
            ],
            resultsLimit: 1
        )

        guard let result = response.matchResults.first else {
            return nil
        }

        let record = try result.1.get()
        return try CloudKitProbe(record: record)
    }
}

