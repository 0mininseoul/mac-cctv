import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return String(format: String(localized: "settings_version_format"), version, build)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("settings_storage_section") {
                    Text("settings_storage_location_note")
                        .foregroundStyle(.secondary)
                    Text("library_auto_delete_note")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label("settings_check_usage_title", systemImage: "internaldrive")
                        .font(.subheadline.weight(.medium))
                    Text("settings_check_usage_body")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label("settings_manual_delete_title", systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                    Text("settings_manual_delete_body")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("settings_about_section") {
                    HStack {
                        Text("settings_version_label")
                        Spacer()
                        Text(appVersionText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("settings_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings_done_button") {
                        dismiss()
                    }
                }
            }
        }
    }
}
