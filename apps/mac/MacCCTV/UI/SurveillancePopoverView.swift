import SwiftUI

struct SurveillancePopoverView: View {
    @ObservedObject var controller: SurveillanceController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("surveillance_title")
                    .font(.headline)
                Text(controller.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button(action: controller.toggleFromButton) {
                Text(controller.isArmed || controller.isSirenActive ? "surveillance_stop" : "surveillance_start")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("c", modifiers: [.control, .command])

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Picker("surveillance_hotkey_label", selection: $controller.selectedShortcut) {
                    ForEach(HotkeyShortcut.all) { shortcut in
                        Text(shortcut.display).tag(shortcut)
                    }
                }

                Picker("surveillance_quality_label", selection: $controller.selectedQuality) {
                    Text("surveillance_quality_low").tag(SurveillanceQuality.low)
                    Text("surveillance_quality_medium").tag(SurveillanceQuality.medium)
                    Text("surveillance_quality_high").tag(SurveillanceQuality.high)
                }

                Toggle("surveillance_notifications_label", isOn: $controller.notificationsEnabled)
            }

            Text(controller.hotkeyStatusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()

            TipJarView()
            HouseBannerSlot()
        }
        .padding(16)
        .frame(width: 360)
    }
}
