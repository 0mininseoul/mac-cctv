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

                if controller.isEscalationPending {
                    Text(
                        String(
                            format: String(localized: "surveillance_escalation_countdown_format"),
                            controller.escalationSecondsRemaining
                        )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
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

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("surveillance_theft_siren_label", isOn: $controller.theftSirenEnabled)
                    Text("surveillance_theft_siren_caption")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("surveillance_siren_warning_text_label")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("surveillance_siren_warning_text_reset") {
                            controller.resetSirenWarningText()
                        }
                        .controlSize(.small)
                    }

                    TextField(
                        "surveillance_siren_warning_text_placeholder",
                        text: $controller.sirenWarningText,
                        axis: .vertical
                    )
                    .lineLimit(2)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: 46, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                    )
                }
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
