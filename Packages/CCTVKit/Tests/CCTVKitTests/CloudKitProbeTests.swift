import CloudKit
import XCTest
@testable import CCTVKit

final class CloudKitProbeTests: XCTestCase {
    func testProbeRoundTripsThroughCKRecord() throws {
        let createdAt = Date(timeIntervalSince1970: 1_783_200_000)
        let probe = CloudKitProbe(
            id: "probe-test",
            source: .mac,
            message: "M0 private database smoke test",
            createdAt: createdAt,
            deviceName: "Test Mac"
        )

        let record = probe.makeRecord()
        let roundTrip = try CloudKitProbe(record: record)

        XCTAssertEqual(roundTrip, probe)
        XCTAssertEqual(record.recordType, CKSchema.RecordType.testProbe)
    }

    func testSchemaUsesPrivateCloudKitContainerContract() {
        XCTAssertEqual(CKSchema.containerIdentifier, "iCloud.com.youngminpark.maccctv")
        XCTAssertEqual(CKSchema.RecordType.session, "Session")
        XCTAssertEqual(CKSchema.RecordType.chunk, "Chunk")
        XCTAssertEqual(CKSchema.RecordType.event, "Event")
        XCTAssertEqual(CKSchema.RecordType.signal, "Signal")
    }
}

