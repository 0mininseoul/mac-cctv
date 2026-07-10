import AVKit
import CCTVKit
import SwiftUI
import UIKit

struct SessionPlaybackView: View {
    @StateObject private var viewModel: SessionPlaybackViewModel
    @StateObject private var webRTCReceiver: WebRTCReceiver
    @State private var showEndConfirmation = false
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
            ZStack {
                if webRTCReceiver.usesRealtimeSurface && viewModel.isLive {
                    WebRTCVideoView(rendererView: webRTCReceiver.rendererView)
                        .background(.black)
                } else {
                    VideoPlayer(player: viewModel.player)
                        .background(.black)
                }

                // Prominent centered overlay while the realtime stream is still
                // negotiating — replaces the old tiny corner chip that was easy to miss.
                if viewModel.isLive && webRTCReceiver.isConnectingLive {
                    LiveConnectingOverlay(statusText: webRTCReceiver.statusText)
                }
            }
            .frame(minHeight: 260)

            if viewModel.isLive {
                LiveControlBar(
                    viewModel: viewModel,
                    webRTCReceiver: webRTCReceiver,
                    onRequestEnd: { showEndConfirmation = true }
                )
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
        .confirmationDialog(
            "end_session_confirm_title",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("end_session_confirm_action", role: .destructive) {
                viewModel.sendEndSession()
            }
            Button("end_session_confirm_cancel", role: .cancel) {}
        } message: {
            Text("end_session_confirm_message")
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

/// Big centered "connecting…" overlay shown over the black video surface while the
/// realtime stream negotiates, so the loading state is obvious instead of a tiny chip.
private struct LiveConnectingOverlay: View {
    let statusText: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("live_connecting_overlay_title")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

/// Compact live control row: a thin hold-to-siren control on the left and a remote
/// end-session button on the right, with a single caption line for hint/status —
/// about a third the height of the old stacked layout.
private struct LiveControlBar: View {
    @ObservedObject var viewModel: SessionPlaybackViewModel
    @ObservedObject var webRTCReceiver: WebRTCReceiver
    let onRequestEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if viewModel.isSirenActive {
                    Button {
                        viewModel.sendSilenceSiren()
                    } label: {
                        Label("silence_siren_button_title", systemImage: "speaker.slash.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(viewModel.isSendingSilenceSiren)
                } else {
                    SirenCommandButton(isSending: viewModel.isSendingSirenCommand) {
                        if webRTCReceiver.sendSirenCommandOverRealtimeChannel() {
                            viewModel.markRealtimeSirenCommandSent()
                        } else {
                            viewModel.sendSirenCommand()
                        }
                    }
                }

                Button(role: .destructive) {
                    onRequestEnd()
                } label: {
                    Label("end_session_button_title", systemImage: "stop.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 38)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(viewModel.isSendingEndSession)
            }

            if let caption = controlCaption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if viewModel.isEscalationPending {
                HStack(spacing: 10) {
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
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isSendingEscalationDismiss)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    /// One shared caption line: prefers whatever action feedback is live, otherwise
    /// the hold hint so first-time users know the siren needs a long press.
    private var controlCaption: String? {
        if !viewModel.endSessionStatusText.isEmpty {
            return viewModel.endSessionStatusText
        }
        if viewModel.isSirenActive {
            return viewModel.silenceSirenStatusText.isEmpty ? nil : viewModel.silenceSirenStatusText
        }
        if !viewModel.sirenCommandStatusText.isEmpty {
            return viewModel.sirenCommandStatusText
        }
        return String(localized: "siren_button_hold_hint")
    }
}

private struct SirenCommandButton: View {
    let isSending: Bool
    let action: () -> Void
    private let holdDuration: TimeInterval = 0.8
    @State private var isPressing = false
    @State private var fillProgress: CGFloat = 0

    var body: some View {
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
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
