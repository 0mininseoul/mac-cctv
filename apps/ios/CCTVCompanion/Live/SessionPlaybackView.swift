import AVKit
import CCTVKit
import SwiftUI

struct SessionPlaybackView: View {
    @StateObject private var viewModel: SessionPlaybackViewModel
    @StateObject private var webRTCReceiver: WebRTCReceiver
    private let session: SurveillanceSession

    init(session: SurveillanceSession) {
        self.session = session
        _viewModel = StateObject(wrappedValue: SessionPlaybackViewModel(session: session))
        _webRTCReceiver = StateObject(wrappedValue: WebRTCReceiver(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if webRTCReceiver.usesRealtimeSurface {
                    WebRTCVideoView(rendererView: webRTCReceiver.rendererView)
                        .background(.black)
                } else {
                    VideoPlayer(player: viewModel.player)
                        .background(.black)
                }

                if session.status == .recording {
                    Text(webRTCReceiver.statusText)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
            .frame(minHeight: 260)

            List {
                Section("playback_status_section") {
                    LabeledContent("playback_mode_label") {
                        Text(modeText)
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
            webRTCReceiver.start()
            viewModel.setPlaybackActive(webRTCReceiver.usesDelayedPlayback)
        }
        .onDisappear {
            webRTCReceiver.stop()
            viewModel.stop()
        }
        .onChange(of: webRTCReceiver.usesDelayedPlayback) { _, usesDelayedPlayback in
            viewModel.setPlaybackActive(usesDelayedPlayback)
        }
    }

    private var modeText: LocalizedStringKey {
        guard viewModel.isLive else {
            return "playback_mode_replay"
        }

        switch webRTCReceiver.viewingMode {
        case .connecting:
            return "playback_mode_connecting"
        case .realtime:
            return "playback_mode_realtime"
        case .delayedFallback:
            return "playback_mode_live"
        }
    }
}
