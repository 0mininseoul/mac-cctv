import CCTVKit
import SwiftUI

struct IOSCloudKitProbeView: View {
    @ObservedObject var viewModel: IOSCloudKitProbeViewModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("probe_title")
                        .font(.headline)
                    Text("probe_subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("probe_cloudkit_section") {
                LabeledContent("probe_container_label", value: CKSchema.containerIdentifier)
                Text("probe_private_db_label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("probe_actions_section") {
                Button("probe_account_check") {
                    viewModel.checkAccount()
                }
                Button("probe_write") {
                    viewModel.writeProbe()
                }
                Button("probe_read") {
                    viewModel.readLatestProbe()
                }
            }
            .disabled(viewModel.isWorking)

            Section("probe_status_section") {
                Text(viewModel.status)
                    .textSelection(.enabled)
            }

            if let latestProbe = viewModel.latestProbe {
                Section("probe_latest_title") {
                    LabeledContent("probe_source_label", value: viewModel.localizedSource(latestProbe.source))
                    LabeledContent("probe_device_label", value: latestProbe.deviceName)
                    LabeledContent("probe_created_label") {
                        Text(latestProbe.createdAt, format: .dateTime)
                    }
                }
            }
        }
    }
}

