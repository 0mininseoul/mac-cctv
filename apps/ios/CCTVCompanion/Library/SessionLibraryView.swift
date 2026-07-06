import CCTVKit
import SwiftUI

struct SessionLibraryView: View {
    @StateObject private var viewModel = SessionLibraryViewModel()
    @State private var isShowingSettings = false

    var body: some View {
        List {
            Section {
                if viewModel.sessions.isEmpty {
                    Text("library_empty_message")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.sessions) { item in
                        NavigationLink(value: item.session.id) {
                            sessionRow(item)
                        }
                    }
                    .onDelete { offsets in
                        viewModel.delete(at: offsets)
                    }
                }
            }

            Section("library_status_section") {
                Text(viewModel.statusText)
                    .textSelection(.enabled)
            }

            Section {
                TipJarView()
            }

            HouseBannerSlot()
        }
        .navigationTitle("library_title")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.load()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("settings_title")
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
    }

    private func sessionRow(_ item: SessionListItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.session.startedAt, format: .dateTime.month().day().hour().minute())
                    .font(.headline)
                Spacer()
                statusLabel(item)
            }

            HStack(spacing: 10) {
                Label(viewModel.durationText(for: item), systemImage: "clock")
                Label(item.session.deviceName, systemImage: "macbook")
                if item.eventCount > 0 {
                    Label("\(item.eventCount)", systemImage: "bell")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func statusLabel(_ item: SessionListItem) -> some View {
        Text(item.isLive ? LocalizedStringKey("library_status_live") : LocalizedStringKey("library_status_ended"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(item.isLive ? .green : .secondary)
    }
}
