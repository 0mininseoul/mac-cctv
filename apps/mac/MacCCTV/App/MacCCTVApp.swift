import SwiftUI

@main
struct MacCCTVApp: App {
    @StateObject private var viewModel = MacCloudKitProbeViewModel()

    init() {
        M0ProbeLaunchHandler.runIfRequested()
        M1CaptureLaunchHandler.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra("mac_menu_title", systemImage: viewModel.isWorking ? "icloud.and.arrow.up" : "video.badge.checkmark") {
            MacCloudKitProbeView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
