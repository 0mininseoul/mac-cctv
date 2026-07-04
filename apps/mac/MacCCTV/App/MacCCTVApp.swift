import SwiftUI

@main
struct MacCCTVApp: App {
    @StateObject private var viewModel = MacCloudKitProbeViewModel()

    var body: some Scene {
        MenuBarExtra("mac_menu_title", systemImage: viewModel.isWorking ? "icloud.and.arrow.up" : "video.badge.checkmark") {
            MacCloudKitProbeView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

