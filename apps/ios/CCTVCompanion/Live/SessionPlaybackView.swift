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

                // Ended-session replay is still fetching/composing — show a spinner
                // so the wait isn't a blank tap-and-nothing-happens screen.
                if !viewModel.isLive && viewModel.isPreparingReplay {
                    ReplayLoadingOverlay()
                }

                // Live, but the realtime stream gave up *and* the session has stopped
                // gaining footage — the Mac is unreachable (asleep / offline), e.g. its
                // lid was closed. Say so instead of showing an endless black screen.
                if viewModel.isLive && webRTCReceiver.usesDelayedPlayback && viewModel.liveContentIsStale {
                    MacUnreachableOverlay()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
            .layoutPriority(1)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isPreparingReplay)
            .animation(.easeInOut(duration: 0.2), value: viewModel.liveContentIsStale)
            .animation(.easeInOut(duration: 0.2), value: webRTCReceiver.usesDelayedPlayback)

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
        .alert(
            "end_session_confirm_title",
            isPresented: $showEndConfirmation
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

/// Spinner shown over the black video surface while an ended session's recording is
/// being fetched and stitched, before the first frame is playable.
private struct ReplayLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("replay_loading_title")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

/// Shown on a live session when the realtime stream couldn't connect and no delayed
/// footage is arriving — i.e. the Mac is unreachable (most often asleep because its
/// lid was closed). Clearer than an endless black screen.
private struct MacUnreachableOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
            VStack(spacing: 14) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("live_unreachable_title")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("live_unreachable_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

/// Bottom control dock for a live session. Fixed, compact height (the video takes
/// the rest of the screen) with a clear hierarchy: the siren is the single red
/// emergency action — a hold-to-activate pill whose gradient sweeps as you hold —
/// and ending the session is a neutral, narrow secondary. The hold affordance lives
/// in the pill's own label, so no separate permanent hint line is needed; the
/// caption slot below is used only for transient action status.
private struct LiveControlBar: View {
    @ObservedObject var viewModel: SessionPlaybackViewModel
    @ObservedObject var webRTCReceiver: WebRTCReceiver
    let onRequestEnd: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Group {
                    if viewModel.isSirenActive {
                        SilenceSirenButton(isSending: viewModel.isSendingSilenceSiren) {
                            viewModel.sendSilenceSiren()
                        }
                    } else {
                        SirenHoldButton(isSending: viewModel.isSendingSirenCommand) {
                            if webRTCReceiver.sendSirenCommandOverRealtimeChannel() {
                                viewModel.markRealtimeSirenCommandSent()
                            } else {
                                viewModel.sendSirenCommand()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                EndSessionButton(isSending: viewModel.isSendingEndSession, action: onRequestEnd)
            }
            .frame(height: LiveControlMetrics.height)

            if let status = controlStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .transition(.opacity)
            }

            if viewModel.isEscalationPending {
                EscalationCountdownStrip(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSirenActive)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isEscalationPending)
    }

    /// Transient action feedback only (sending / sent / failed). The hold hint now
    /// lives inside the siren pill's label, so there's no permanent hint line.
    private var controlStatus: String? {
        if !viewModel.endSessionStatusText.isEmpty {
            return viewModel.endSessionStatusText
        }
        if viewModel.isSirenActive {
            return viewModel.silenceSirenStatusText.isEmpty ? nil : viewModel.silenceSirenStatusText
        }
        if !viewModel.sirenCommandStatusText.isEmpty {
            return viewModel.sirenCommandStatusText
        }
        return nil
    }
}

private enum LiveControlMetrics {
    static let height: CGFloat = 58
    static let corner: CGFloat = 18
}

/// Hold-to-activate siren pill. A red gradient sweeps left→right as you hold, the
/// label flips from the "hold" call-to-action to "keep holding", a soft red glow
/// grows with progress, and a success haptic fires on completion. Fixed height so it
/// never balloons to fill the screen.
private struct SirenHoldButton: View {
    let isSending: Bool
    let action: () -> Void
    private let holdDuration: TimeInterval = 0.8
    @State private var isPressing = false
    @State private var fillProgress: CGFloat = 0
    @State private var fireHaptic = false

    private var shape: some Shape {
        RoundedRectangle(cornerRadius: LiveControlMetrics.corner, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(Color.red.opacity(0.10))

            GeometryReader { geometry in
                shape
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.87, green: 0.17, blue: 0.19), Color(red: 0.69, green: 0.06, blue: 0.09)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * fillProgress)
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.3.fill")
                Text(isPressing ? "siren_button_hold_progress" : "siren_button_hold_cta")
            }
            .font(.headline)
            .foregroundStyle(fillProgress > 0.5 ? Color.white : Color.red)
            .animation(.easeInOut(duration: 0.15), value: fillProgress > 0.5)
        }
        .frame(height: LiveControlMetrics.height)
        .overlay(shape.stroke(Color.red.opacity(0.4), lineWidth: 1))
        .clipShape(shape)
        .shadow(color: Color.red.opacity(Double(fillProgress) * 0.4), radius: 12, y: 4)
        .opacity(isSending ? 0.55 : 1)
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: holdDuration,
            pressing: { pressing in
                guard !isSending else {
                    return
                }
                isPressing = pressing
                withAnimation(pressing ? .linear(duration: holdDuration) : .easeOut(duration: 0.25)) {
                    fillProgress = pressing ? 1 : 0
                }
            },
            perform: {
                guard !isSending else {
                    return
                }
                isPressing = false
                fireHaptic.toggle()
                withAnimation(.easeOut(duration: 0.25)) {
                    fillProgress = 0
                }
                action()
            }
        )
        .sensoryFeedback(.success, trigger: fireHaptic)
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

/// Prominent red button shown while the Mac siren is sounding, to turn it off.
private struct SilenceSirenButton: View {
    let isSending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("silence_siren_button_title", systemImage: "speaker.slash.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: LiveControlMetrics.height)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .clipShape(RoundedRectangle(cornerRadius: LiveControlMetrics.corner, style: .continuous))
        .disabled(isSending)
    }
}

/// Neutral, narrow secondary control — deliberately not red so it doesn't compete
/// with the siren for "danger" weight. Icon-over-label keeps it compact.
private struct EndSessionButton: View {
    let isSending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("end_session_button_title")
                    .font(.caption2.weight(.semibold))
            }
            .frame(width: 66, height: LiveControlMetrics.height)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: LiveControlMetrics.corner, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .opacity(isSending ? 0.55 : 1)
        .disabled(isSending)
        .accessibilityLabel("end_session_button_title")
    }
}

/// Orange countdown strip shown only while an auto-siren escalation is pending, with
/// a one-tap dismiss. Visually distinct from the siren/end row.
private struct EscalationCountdownStrip: View {
    @ObservedObject var viewModel: SessionPlaybackViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(
                String(
                    format: String(localized: "escalation_countdown_format"),
                    viewModel.escalationSecondsRemaining
                )
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)

            Spacer(minLength: 8)

            Button {
                viewModel.sendEscalationDismiss()
            } label: {
                Label("escalation_dismiss_button_title", systemImage: "xmark.shield")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.orange)
            .disabled(viewModel.isSendingEscalationDismiss)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }
}
