import AVKit
import CCTVKit
import SwiftUI
import UIKit

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

            if viewModel.isLive {
                VStack(alignment: .leading, spacing: 8) {
                    SirenCommandButton(isSending: viewModel.isSendingSirenCommand) {
                        if webRTCReceiver.sendSirenCommandOverRealtimeChannel() {
                            viewModel.markRealtimeSirenCommandSent()
                        } else {
                            viewModel.sendSirenCommand()
                        }
                    }

                    if !viewModel.sirenCommandStatusText.isEmpty {
                        Text(viewModel.sirenCommandStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }

            if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            if !viewModel.exportStatusText.isEmpty {
                Text(viewModel.exportStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            if !viewModel.playlist.missingRanges.isEmpty {
                List {
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
            }
        }
        .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.hasReplayableVideo {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.exportVideoForSharing()
                    } label: {
                        if viewModel.isExportingVideo {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(viewModel.isExportingVideo)
                    .accessibilityLabel("save_video_button")
                }
            }
        }
        .sheet(item: Binding(
            get: { viewModel.exportedVideoURL },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissExportedVideo()
                }
            }
        )) { identifiableURL in
            ActivityView(activityItems: [identifiableURL.url])
        }
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
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SirenCommandButton: View {
    let isSending: Bool
    let action: () -> Void
    @State private var isPressing = false

    var body: some View {
        Label("siren_button_title", systemImage: "speaker.wave.3.fill")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
            .foregroundStyle(.red)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(isPressing ? 0.22 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
            )
            .opacity(isSending ? 0.55 : 1)
            .contentShape(Rectangle())
            .onLongPressGesture(
                minimumDuration: 0.8,
                pressing: { pressing in
                    guard !isSending else {
                        return
                    }
                    isPressing = pressing
                },
                perform: {
                    guard !isSending else {
                        return
                    }
                    isPressing = false
                    action()
                }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("siren_button_accessibility_hint")
            .accessibilityAction {
                guard !isSending else {
                    return
                }
                action()
            }
    }
}
