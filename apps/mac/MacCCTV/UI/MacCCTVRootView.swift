import SwiftUI

struct MacCCTVRootView: View {
    @ObservedObject var controller: SurveillanceController
    @AppStorage("m8.onboarding.completed") private var isOnboardingCompleted = false

    var body: some View {
        if isOnboardingCompleted {
            SurveillancePopoverView(controller: controller)
        } else {
            MacOnboardingView(theftSirenEnabled: $controller.theftSirenEnabled) {
                isOnboardingCompleted = true
            }
        }
    }
}
