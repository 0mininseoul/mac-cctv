import SwiftUI

@main
struct MacCCTVApp: App {
    @StateObject private var controller = SurveillanceController()

    init() {
        M0ProbeLaunchHandler.runIfRequested()
        M1CaptureLaunchHandler.runIfRequested()
        M2UploadLaunchHandler.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra("mac_menu_title", systemImage: controller.menuSystemImage) {
            SurveillancePopoverView(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}
