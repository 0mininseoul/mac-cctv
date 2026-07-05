import CloudKit
import Foundation

public enum M0ProbeCommand {
    public static let writeArgument = "--m0-probe-write"
    public static let readArgument = "--m0-probe-read"

    public static func runIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        source: ProbeSource,
        deviceName: String,
        store: CloudKitStore = CloudKitStore()
    ) async throws -> String? {
        if arguments.contains(writeArgument) {
            let status = try await store.accountStatus()
            let probe = try await store.saveM0SharedProbe(source: source, deviceName: deviceName)
            return resultLine(prefix: "M0_PROBE_WRITE_OK", accountStatus: status, probe: probe)
        }

        if arguments.contains(readArgument) {
            let status = try await store.accountStatus()
            let probe = try await store.fetchM0SharedProbe()
            return resultLine(prefix: "M0_PROBE_READ_OK", accountStatus: status, probe: probe)
        }

        return nil
    }

    private static func resultLine(prefix: String, accountStatus: CKAccountStatus, probe: CloudKitProbe) -> String {
        [
            prefix,
            "account=\(accountStatus.debugName)",
            "id=\(probe.id)",
            "source=\(probe.source.rawValue)",
            "device=\(probe.deviceName)",
            "createdAt=\(probe.createdAt.timeIntervalSince1970)"
        ].joined(separator: " ")
    }
}

private extension CKAccountStatus {
    var debugName: String {
        switch self {
        case .available:
            "available"
        case .noAccount:
            "noAccount"
        case .restricted:
            "restricted"
        case .couldNotDetermine:
            "couldNotDetermine"
        case .temporarilyUnavailable:
            "temporarilyUnavailable"
        @unknown default:
            "unknown"
        }
    }
}

