import SwiftUI

@main
struct CCTVCompanionApp: App {
    init() {
        M0ProbeLaunchHandler.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                IOSCloudKitProbeView(viewModel: IOSCloudKitProbeViewModel())
                    .navigationTitle("ios_navigation_title")
            }
        }
    }
}
