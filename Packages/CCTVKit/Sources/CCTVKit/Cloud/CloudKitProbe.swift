import CloudKit
import Foundation

public enum ProbeSource: String, CaseIterable, Sendable {
    case mac
    case ios
}

public struct CloudKitProbe: Identifiable, Equatable, Sendable {
    public let id: String
    public var source: ProbeSource
    public var message: String
    public var createdAt: Date
    public var deviceName: String

    public init(
        id: String = UUID().uuidString,
        source: ProbeSource,
        message: String,
        createdAt: Date = Date(),
        deviceName: String
    ) {
        self.id = id
        self.source = source
        self.message = message
        self.createdAt = createdAt
        self.deviceName = deviceName
    }

    public init(record: CKRecord) throws {
        guard let sourceValue = record[CKSchema.TestProbe.source] as? String,
              let source = ProbeSource(rawValue: sourceValue),
              let message = record[CKSchema.TestProbe.message] as? String,
              let createdAt = record[CKSchema.TestProbe.createdAt] as? Date,
              let deviceName = record[CKSchema.TestProbe.deviceName] as? String else {
            throw CloudKitStoreError.malformedRecord(record.recordID.recordName)
        }

        self.id = record.recordID.recordName
        self.source = source
        self.message = message
        self.createdAt = createdAt
        self.deviceName = deviceName
    }

    public func makeRecord() -> CKRecord {
        let record = CKRecord(
            recordType: CKSchema.RecordType.testProbe,
            recordID: CKRecord.ID(recordName: id)
        )
        record[CKSchema.TestProbe.source] = source.rawValue as CKRecordValue
        record[CKSchema.TestProbe.message] = message as CKRecordValue
        record[CKSchema.TestProbe.createdAt] = createdAt as CKRecordValue
        record[CKSchema.TestProbe.deviceName] = deviceName as CKRecordValue
        return record
    }
}

