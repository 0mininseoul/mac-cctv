import AVKit
import CCTVKit
import SwiftUI

struct SessionPlaybackView: View {
    @StateObject private var viewModel: SessionPlaybackViewModel
    private let session: SurveillanceSession

    init(session: SurveillanceSession) {
        self.session = session
        _viewModel = StateObject(wrappedValue: SessionPlaybackViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: viewModel.player)
                .background(.black)
                .frame(minHeight: 260)

            List {
                Section("playback_status_section") {
                    LabeledContent("playback_mode_label") {
                        Text(viewModel.isLive ? LocalizedStringKey("playback_mode_live") : LocalizedStringKey("playback_mode_replay"))
                    }
                    LabeledContent("playback_chunks_label", value: "\(viewModel.playableChunkCount)")
                    Text(viewModel.statusText)
                        .textSelection(.enabled)
                }

                if !viewModel.playlist.missingRanges.isEmpty {
                    Section("playback_missing_section") {
                        ForEach(viewModel.playlist.missingRanges, id: \.startIndex) { range in
                            Text(
                                String(
                                    format: String(localized: "playback_missing_range_format"),
                                    range.startIndex,
                                    range.endIndex
                                )
                            )
                        }
                    }
                }

                Section {
                    Text("library_auto_delete_note")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
