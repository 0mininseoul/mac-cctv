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
        _webRTCReceiver = StateObject(wrappedValue: WebRTCReceiver(
            session: session,
            diagnostics: { line in
                IOSDiagnostics.append(line, filename: "m6-receiver-result.txt")
            }
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if webRTCReceiver.usesRealtimeSurface && viewModel.isLive {
                    WebRTCVideoView(rendererView: webRTCReceiver.rendererView)
                        .background(.black)
                } else {
                    VideoPlayer(player: viewModel.player)
                        .background(.black)
                }

                if viewModel.isLive {
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
                    if viewModel.isSirenActive {
                        Button {
                            viewModel.sendSilenceSiren()
                        } label: {
                            Label("silence_siren_button_title", systemImage: "speaker.slash.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(viewModel.isSendingSilenceSiren)

                        if !viewModel.silenceSirenStatusText.isEmpty {
                            Text(viewModel.silenceSirenStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } else {
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

                    if viewModel.isEscalationPending {
                        Text(
                            String(
                                format: String(localized: "escalation_countdown_format"),
                                viewModel.escalationSecondsRemaining
                            )
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)

                        Button {
                            viewModel.sendEscalationDismiss()
                        } label: {
                            Label("escalation_dismiss_button_title", systemImage: "xmark.shield")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isSendingEscalationDismiss)

                        if !viewModel.escalationDismissStatusText.isEmpty {
                            Text(viewModel.escalationDismissStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
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

            if !viewModel.playlist.missingRanges.isEmpty && !viewModel.endedRemotely {
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
        .onChange(of: viewModel.endedRemotely) { _, ended in
            // Mac reported the session ended mid-watch: tear down the live WebRTC
            // surface so the view falls back to replay of the finished recording.
            if ended {
                webRTCReceiver.stop()
                viewModel.setPlaybackActive(true)
            }
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
    private let holdDuration: TimeInterval = 0.8
    @State private var isPressing = false
    @State private var fillProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Fills left-to-right while held so it's obvious this is a
                // hold-to-activate control, not a tap.
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.28))
                        .frame(width: geometry.size.width * fillProgress)
                }

                Label(
                    isPressing ? "siren_button_hold_progress" : "siren_button_title",
                    systemImage: "speaker.wave.3.fill"
                )
                .font(.headline)
                .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("siren_button_hold_hint")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .opacity(isSending ? 0.55 : 1)
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: holdDuration,
            pressing: { pressing in
                guard !isSending else {
                    return
                }
                isPressing = pressing
                withAnimation(pressing ? .linear(duration: holdDuration) : .easeOut(duration: 0.2)) {
                    fillProgress = pressing ? 1 : 0
                }
            },
            perform: {
                guard !isSending else {
                    return
                }
                isPressing = false
                withAnimation(.easeOut(duration: 0.2)) {
                    fillProgress = 0
                }
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
