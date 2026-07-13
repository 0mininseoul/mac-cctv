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

/// Live control bar with a deliberate hierarchy: the siren is the single red
/// emergency action (hold-to-activate, full width), and ending the session is a
/// neutral, compact secondary tap — so the two never read as competing red buttons
/// (the old awkwardness). One caption line carries the hold hint or action status.
private struct LiveControlBar: View {
    @ObservedObject var viewModel: SessionPlaybackViewModel
    @ObservedObject var webRTCReceiver: WebRTCReceiver
    let onRequestEnd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
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

            if let caption = controlCaption {
                Text(caption)
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
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSirenActive)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isEscalationPending)
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

private enum LiveControlMetrics {
    static let height: CGFloat = 52
    static let corner: CGFloat = 14
}

/// Hold-to-activate siren. A gradient fills left→right while pressed so the
/// hold-not-tap affordance is unmistakable, the label flips to a "keep holding"
/// state, and a success haptic fires on completion.
private struct SirenHoldButton: View {
    let isSending: Bool
    let action: () -> Void
    private let holdDuration: TimeInterval = 0.8
    @State private var isPressing = false
    @State private var fillProgress: CGFloat = 0
    @State private var fireHaptic = false

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: LiveControlMetrics.corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.95), Color(red: 0.74, green: 0.09, blue: 0.11)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * fillProgress)
            }

            Label(
                isPressing ? "siren_button_hold_progress" : "siren_button_title",
                systemImage: "speaker.wave.3.fill"
            )
            .font(.headline)
            .foregroundStyle(fillProgress > 0.55 ? Color.white : Color.red)
            .animation(.easeInOut(duration: 0.15), value: fillProgress > 0.55)
        }
        .frame(maxWidth: .infinity, minHeight: LiveControlMetrics.height)
        .background(
            RoundedRectangle(cornerRadius: LiveControlMetrics.corner, style: .continuous)
                .fill(Color.red.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiveControlMetrics.corner, style: .continuous)
                .stroke(Color.red.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LiveControlMetrics.corner, style: .continuous))
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
                fireHaptic.toggle()
                withAnimation(.easeOut(duration: 0.2)) {
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
                .frame(maxWidth: .infinity, minHeight: LiveControlMetrics.height)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .clipShape(RoundedRectangle(cornerRadius: LiveControlMetrics.corner, style: .continuous))
        .disabled(isSending)
    }
}

/// Neutral, compact secondary control — deliberately not red so it doesn't compete
/// with the siren for "danger" weight. Icon-over-label keeps it narrow.
private struct EndSessionButton: View {
    let isSending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "stop.fill")
                    .font(.subheadline.weight(.bold))
                Text("end_session_button_title")
                    .font(.caption.weight(.semibold))
            }
            .frame(width: 74, height: LiveControlMetrics.height)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: LiveControlMetrics.corner, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
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
