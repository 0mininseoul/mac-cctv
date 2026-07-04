import CCTVKit
import SwiftUI

struct MacCloudKitProbeView: View {
    @ObservedObject var viewModel: MacCloudKitProbeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("probe_title")
                    .font(.headline)
                Text("probe_subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("probe_container_label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CKSchema.containerIdentifier)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Text("probe_private_db_label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
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

            Text(viewModel.status)
                .font(.caption)
                .foregroundStyle(viewModel.isWorking ? .secondary : .primary)
                .textSelection(.enabled)

            if let latestProbe = viewModel.latestProbe {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("probe_latest_title")
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.localizedSource(latestProbe.source))
                    Text(latestProbe.deviceName)
                    Text(latestProbe.createdAt, style: .date)
                    Text(latestProbe.createdAt, style: .time)
                }
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

