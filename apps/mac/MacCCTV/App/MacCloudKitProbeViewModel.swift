import CCTVKit
import CloudKit
import Foundation

@MainActor
final class MacCloudKitProbeViewModel: ObservableObject {
    @Published var status: String = String(localized: "probe_status_ready")
    @Published var latestProbe: CloudKitProbe?
    @Published var isWorking = false

    private lazy var store = CloudKitStore()
    private let deviceName = Host.current().localizedName ?? "Mac"

    func checkAccount() {
        run(statusKey: "probe_status_checking_account") {
            let accountStatus = try await self.store.accountStatus()
            return self.localizedAccountStatus(accountStatus)
        }
    }

    func writeProbe() {
        run(statusKey: "probe_status_writing") {
            let saved = try await self.store.saveTestProbe(
                source: .mac,
                message: String(localized: "probe_message_m0"),
                deviceName: self.deviceName
            )
            self.latestProbe = saved
            return String(format: String(localized: "probe_status_saved_format"), saved.deviceName)
        }
    }

    func readLatestProbe() {
        run(statusKey: "probe_status_reading") {
            guard let latest = try await self.store.fetchLatestTestProbe() else {
                self.latestProbe = nil
                return String(localized: "probe_status_empty")
            }
            self.latestProbe = latest
            return String(format: String(localized: "probe_status_latest_format"), latest.deviceName)
        }
    }

    func localizedSource(_ source: ProbeSource) -> String {
        switch source {
        case .mac:
            String(localized: "probe_source_mac")
        case .ios:
            String(localized: "probe_source_ios")
        }
    }

    private func run(statusKey: LocalizedStringResource, operation: @escaping () async throws -> String) {
        isWorking = true
        status = String(localized: statusKey)

        Task {
            do {
                status = try await operation()
            } catch {
                status = String(format: String(localized: "probe_status_failed_format"), error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func localizedAccountStatus(_ accountStatus: CKAccountStatus) -> String {
        switch accountStatus {
        case .available:
            String(localized: "probe_status_account_available")
        case .noAccount:
            String(localized: "probe_status_account_no_account")
        case .restricted:
            String(localized: "probe_status_account_restricted")
        case .couldNotDetermine:
            String(localized: "probe_status_account_unknown")
        case .temporarilyUnavailable:
            String(localized: "probe_status_account_temporarily_unavailable")
        @unknown default:
            String(localized: "probe_status_account_unknown")
        }
    }
}
