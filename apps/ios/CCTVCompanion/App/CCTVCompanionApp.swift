import SwiftUI

@main
struct CCTVCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                IOSCloudKitProbeView(viewModel: IOSCloudKitProbeViewModel())
                    .navigationTitle("ios_navigation_title")
            }
        }
    }
}

