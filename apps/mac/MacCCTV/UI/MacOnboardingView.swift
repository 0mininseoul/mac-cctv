import AppKit
import AVFoundation
import CCTVKit
import CloudKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct MacOnboardingView: View {
    let onComplete: () -> Void

    @StateObject private var viewModel = MacOnboardingViewModel()
    @State private var step = MacOnboardingStep.camera

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ProgressView(value: Double(step.rawValue + 1), total: Double(MacOnboardingStep.allCases.count))

            switch step {
            case .camera:
                cameraStep
            case .iCloud:
                iCloudStep
            case .iPhone:
                iPhoneStep
            }

            Divider()

            HStack {
                if step != .camera {
                    Button("onboarding_back") {
                        withAnimation(.snappy) {
                            step = step.previous
                        }
                    }
                }

                Spacer()

                Button(step.primaryButtonKey) {
                    handlePrimaryAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPrimaryButtonDisabled)
            }
        }
        .padding(18)
        .frame(width: 380)
        .task {
            viewModel.refreshCameraAuthorization()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("onboarding_title")
                .font(.headline)
            Text("onboarding_subtitle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cameraStep: some View {
        OnboardingStepLayout(
            systemImage: "camera.fill",
            titleKey: "onboarding_camera_title",
            messageKey: "onboarding_camera_message",
            statusKey: viewModel.cameraStatusKey,
            statusSymbol: viewModel.cameraStatusSymbol
        ) {
            if viewModel.cameraAuthorizationStatus == .denied || viewModel.cameraAuthorizationStatus == .restricted {
                Button("onboarding_open_camera_settings") {
                    viewModel.openCameraPrivacySettings()
                }
            } else if viewModel.cameraAuthorizationStatus == .notDetermined {
                Button("onboarding_camera_request") {
                    Task {
                        await viewModel.requestCameraAuthorization()
                    }
                }
            }
        }
    }

    private var iCloudStep: some View {
        OnboardingStepLayout(
            systemImage: "icloud.fill",
            titleKey: "onboarding_icloud_title",
            messageKey: "onboarding_icloud_message",
            statusKey: viewModel.iCloudStatusKey,
            statusSymbol: viewModel.iCloudStatusSymbol
        ) {
            Button("onboarding_icloud_check") {
                Task {
                    await viewModel.checkICloudAccount()
                }
            }
            .disabled(viewModel.isCheckingICloud)
        }
        .task {
            await viewModel.checkICloudAccount()
        }
    }

    private var iPhoneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingStepTitle(
                systemImage: "iphone",
                titleKey: "onboarding_iphone_title",
                messageKey: "onboarding_iphone_message"
            )

            if let image = viewModel.companionQRCode {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 156, height: 156)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("onboarding_qr_unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text("onboarding_lock_recommendation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        switch step {
        case .camera:
            !viewModel.canContinueFromCamera
        case .iCloud:
            !viewModel.canContinueFromICloud
        case .iPhone:
            false
        }
    }

    private func handlePrimaryAction() {
        if step == .iPhone {
            onComplete()
            return
        }

        withAnimation(.snappy) {
            step = step.next
        }
    }
}

private enum MacOnboardingStep: Int, CaseIterable {
    case camera
    case iCloud
    case iPhone

    var next: MacOnboardingStep {
        switch self {
        case .camera:
            .iCloud
        case .iCloud:
            .iPhone
        case .iPhone:
            .iPhone
        }
    }

    var previous: MacOnboardingStep {
        switch self {
        case .camera:
            .camera
        case .iCloud:
            .camera
        case .iPhone:
            .iCloud
        }
    }

    var primaryButtonKey: LocalizedStringKey {
        switch self {
        case .camera, .iCloud:
            "onboarding_continue"
        case .iPhone:
            "onboarding_finish"
        }
    }
}

private struct OnboardingStepLayout<Actions: View>: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey
    let statusKey: LocalizedStringKey
    let statusSymbol: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingStepTitle(systemImage: systemImage, titleKey: titleKey, messageKey: messageKey)

            HStack(spacing: 8) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(.secondary)
                Text(statusKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            actions
        }
    }
}

private struct OnboardingStepTitle: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 30)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
                Text(messageKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
private final class MacOnboardingViewModel: ObservableObject {
    @Published private(set) var cameraAuthorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published private(set) var iCloudAccountStatus: CKAccountStatus?
    @Published private(set) var isCheckingICloud = false

    private let store = CloudKitStore()
    private let qrRenderer = CompanionQRCodeRenderer()

    var companionQRCode: NSImage? {
        qrRenderer.image(for: CompanionInstallLink.url)
    }

    var canContinueFromCamera: Bool {
        cameraAuthorizationStatus == .authorized
    }

    var canContinueFromICloud: Bool {
        iCloudAccountStatus == .available
    }

    var cameraStatusKey: LocalizedStringKey {
        switch cameraAuthorizationStatus {
        case .authorized:
            "onboarding_camera_status_authorized"
        case .notDetermined:
            "onboarding_camera_status_not_determined"
        case .denied:
            "onboarding_camera_status_denied"
        case .restricted:
            "onboarding_camera_status_restricted"
        @unknown default:
            "onboarding_camera_status_restricted"
        }
    }

    var cameraStatusSymbol: String {
        cameraAuthorizationStatus == .authorized ? "checkmark.circle.fill" : "circle"
    }

    var iCloudStatusKey: LocalizedStringKey {
        guard let iCloudAccountStatus else {
            return "onboarding_icloud_status_not_checked"
        }

        switch iCloudAccountStatus {
        case .available:
            return "onboarding_icloud_status_available"
        case .noAccount:
            return "onboarding_icloud_status_no_account"
        case .restricted:
            return "onboarding_icloud_status_restricted"
        case .couldNotDetermine:
            return "onboarding_icloud_status_unknown"
        case .temporarilyUnavailable:
            return "onboarding_icloud_status_temporarily_unavailable"
        @unknown default:
            return "onboarding_icloud_status_unknown"
        }
    }

    var iCloudStatusSymbol: String {
        iCloudAccountStatus == .available ? "checkmark.circle.fill" : "circle"
    }

    func refreshCameraAuthorization() {
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestCameraAuthorization() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        refreshCameraAuthorization()
    }

    func checkICloudAccount() async {
        guard !isCheckingICloud else {
            return
        }

        isCheckingICloud = true
        defer {
            isCheckingICloud = false
        }

        do {
            iCloudAccountStatus = try await store.accountStatus()
        } catch {
            iCloudAccountStatus = .couldNotDetermine
        }
    }

    func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private enum CompanionInstallLink {
    static let url = URL(string: "https://apps.apple.com/search?term=Mac%20CCTV")!
}

private struct CompanionQRCodeRenderer {
    private let context = CIContext()

    func image(for url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else {
            return nil
        }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 156, height: 156))
    }
}
