import CCTVKit
import Foundation
import SwiftUI
import UIKit
import WebRTC

@MainActor
final class WebRTCReceiver: NSObject, ObservableObject {
    @Published private(set) var viewingMode: LiveViewingMode = .connecting(elapsed: 0)
    @Published private(set) var statusText = String(localized: "live_status_connecting")

    let rendererView = RTCMTLVideoView(frame: .zero)

    private let session: SurveillanceSession
    private let channel: SignalingChannel
    private let diagnostics: (@Sendable (String) -> Void)?
    private let factory: RTCPeerConnectionFactory
    private let policy = LiveConnectionPolicy(timeout: 10)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var peerConnection: RTCPeerConnection?
    private var signalTask: Task<Void, Never>?
    private var modeTask: Task<Void, Never>?
    private var cursor = Date.distantPast
    private var startedAt: Date?
    private var hasReceivedRemoteVideo = false
    private var peerConnectionFailed = false
    private var remoteVideoTrack: RTCVideoTrack?
    private var frameObserver: RemoteFrameObserver?

    init(
        session: SurveillanceSession,
        channel: SignalingChannel? = nil,
        diagnostics: (@Sendable (String) -> Void)? = nil
    ) {
        self.session = session
        self.channel = channel ?? CloudKitSignalingChannel(sessionID: session.id, localSender: .ios)
        self.diagnostics = diagnostics
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        super.init()
        rendererView.videoContentMode = .scaleAspectFit
        rendererView.isEnabled = true
    }

    var usesRealtimeSurface: Bool {
        guard session.status == .recording else {
            return false
        }

        switch viewingMode {
        case .connecting, .realtime:
            return true
        case .delayedFallback:
            return false
        }
    }

    var usesDelayedPlayback: Bool {
        !usesRealtimeSurface
    }

    func start() {
        guard session.status == .recording, signalTask == nil else {
            return
        }

        do {
            startedAt = Date()
            hasReceivedRemoteVideo = false
            peerConnectionFailed = false
            viewingMode = .connecting(elapsed: 0)
            statusText = String(localized: "live_status_connecting")
            peerConnection = try makePeerConnection()
            startSignalLoop()
            startModeLoop()
        } catch {
            peerConnectionFailed = true
            refreshMode(now: Date())
            statusText = String(format: String(localized: "live_status_failed_format"), error.localizedDescription)
        }
    }

    func stop() {
        signalTask?.cancel()
        signalTask = nil
        modeTask?.cancel()
        modeTask = nil
        remoteVideoTrack?.remove(rendererView)
        if let frameObserver {
            remoteVideoTrack?.remove(frameObserver)
        }
        remoteVideoTrack = nil
        frameObserver = nil
        peerConnection?.close()
        peerConnection = nil
    }

    private func makePeerConnection() throws -> RTCPeerConnection {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        configuration.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        ]

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
        guard let connection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw WebRTCReceiverError.couldNotCreatePeerConnection
        }
        return connection
    }

    private func startSignalLoop() {
        signalTask?.cancel()
        signalTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.receiveOnce()
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func startModeLoop() {
        modeTask?.cancel()
        modeTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshMode(now: Date())
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func receiveOnce() async {
        do {
            let messages = try await channel.receive(after: cursor)
            cursor = messages.map(\.createdAt).max() ?? cursor
            for message in messages {
                try await handle(message)
            }
        } catch {
            statusText = String(format: String(localized: "live_status_signal_failed_format"), error.localizedDescription)
        }
    }

    private func handle(_ message: SignalMessage) async throws {
        guard let peerConnection else {
            return
        }

        switch message.kind {
        case .offer:
            let payload = try decoder.decode(SessionDescriptionSignalPayload.self, from: Data(message.payload.utf8))
            let description = RTCSessionDescription(
                type: RTCSessionDescription.type(for: payload.type),
                sdp: payload.sdp
            )
            try await peerConnection.setRemote(description)
            let answer = try await peerConnection.makeAnswer()
            try await peerConnection.setLocal(answer)
            try await send(description: answer, kind: .answer)
            statusText = String(localized: "live_status_answer_sent")
        case .ice:
            let payload = try decoder.decode(IceCandidateSignalPayload.self, from: Data(message.payload.utf8))
            let candidate = RTCIceCandidate(
                sdp: payload.sdp,
                sdpMLineIndex: payload.sdpMLineIndex,
                sdpMid: payload.sdpMid
            )
            try await peerConnection.add(candidate)
            diagnostics?("M6_RECEIVER_REMOTE_ICE_ADDED session=\(session.id) mid=\(payload.sdpMid ?? "nil") index=\(payload.sdpMLineIndex)")
        case .answer, .sirenCommand:
            return
        }
    }

    private func attach(videoTrack: RTCVideoTrack) {
        remoteVideoTrack?.remove(rendererView)
        if let frameObserver {
            remoteVideoTrack?.remove(frameObserver)
        }

        let observer = RemoteFrameObserver { [weak self] in
            Task { @MainActor [weak self] in
                self?.markRemoteFrameReceived()
            }
        }
        remoteVideoTrack = videoTrack
        frameObserver = observer
        videoTrack.add(rendererView)
        videoTrack.add(observer)
        diagnostics?("M6_RECEIVER_TRACK_ATTACHED session=\(session.id)")
        statusText = String(localized: "live_status_waiting_for_frame")
    }

    private func markRemoteFrameReceived() {
        guard !hasReceivedRemoteVideo else {
            return
        }
        hasReceivedRemoteVideo = true
        refreshMode(now: Date())
        diagnostics?("M6_RECEIVER_FRAME_RECEIVED session=\(session.id)")
        statusText = String(localized: "live_status_realtime")
    }

    private func refreshMode(now: Date) {
        guard let startedAt else {
            return
        }

        let nextMode = policy.mode(
            startedAt: startedAt,
            now: now,
            hasReceivedRemoteVideo: hasReceivedRemoteVideo,
            peerConnectionFailed: peerConnectionFailed
        )
        viewingMode = nextMode

        switch nextMode {
        case let .connecting(elapsed):
            statusText = String(format: String(localized: "live_status_connecting_format"), elapsed)
        case .realtime:
            statusText = String(localized: "live_status_realtime")
        case let .delayedFallback(reason):
            statusText = fallbackStatusText(reason: reason)
            peerConnection?.close()
        }
    }

    private func fallbackStatusText(reason: LiveFallbackReason) -> String {
        switch reason {
        case .timeout:
            String(localized: "live_status_timeout_fallback")
        case .connectionFailed:
            String(localized: "live_status_connection_fallback")
        }
    }

    private func send(description: RTCSessionDescription, kind: SignalKind) async throws {
        let payload = SessionDescriptionSignalPayload(
            type: RTCSessionDescription.string(for: description.type),
            sdp: description.sdp
        )
        let data = try encoder.encode(payload)
        try await channel.send(
            SignalMessage(
                id: "\(session.id)-ios-\(kind.rawValue)-\(UUID().uuidString)",
                sessionID: session.id,
                kind: kind,
                payload: String(decoding: data, as: UTF8.self),
                sender: .ios,
                createdAt: Date()
            )
        )
    }

    private func send(candidate: RTCIceCandidate) async {
        do {
            let payload = IceCandidateSignalPayload(
                sdp: candidate.sdp,
                sdpMLineIndex: candidate.sdpMLineIndex,
                sdpMid: candidate.sdpMid
            )
            let data = try encoder.encode(payload)
            try await channel.send(
                SignalMessage(
                    id: "\(session.id)-ios-ice-\(UUID().uuidString)",
                    sessionID: session.id,
                    kind: .ice,
                    payload: String(decoding: data, as: UTF8.self),
                    sender: .ios,
                    createdAt: Date()
                )
            )
            diagnostics?("M6_RECEIVER_LOCAL_ICE_SENT session=\(session.id) mid=\(candidate.sdpMid ?? "nil") index=\(candidate.sdpMLineIndex)")
        } catch {
            statusText = String(format: String(localized: "live_status_signal_failed_format"), error.localizedDescription)
            diagnostics?("M6_RECEIVER_ICE_SEND_FAILED session=\(session.id) error=\(error.localizedDescription)")
        }
    }
}

extension WebRTCReceiver: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let videoTrack = stream.videoTracks.first else {
            return
        }
        Task { @MainActor [weak self] in
            self?.attach(videoTrack: videoTrack)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            diagnostics?("M6_RECEIVER_ICE_STATE session=\(session.id) state=\(newState.rawValue)")
            if newState == .failed || newState == .closed || (newState == .disconnected && hasReceivedRemoteVideo) {
                self.peerConnectionFailed = true
                self.refreshMode(now: Date())
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor [weak self] in
            await self?.send(candidate: candidate)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            diagnostics?("M6_RECEIVER_CONNECTION_STATE session=\(session.id) state=\(newState.rawValue)")
            if newState == .failed || newState == .closed || (newState == .disconnected && hasReceivedRemoteVideo) {
                self.peerConnectionFailed = true
                self.refreshMode(now: Date())
            }
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd receiver: RTCRtpReceiver,
        streams: [RTCMediaStream]
    ) {
        guard let videoTrack = receiver.track as? RTCVideoTrack else {
            return
        }
        Task { @MainActor [weak self] in
            self?.attach(videoTrack: videoTrack)
        }
    }
}

struct WebRTCVideoView: UIViewRepresentable {
    let rendererView: RTCMTLVideoView

    func makeUIView(context: Context) -> RTCMTLVideoView {
        rendererView
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {}
}

private final class RemoteFrameObserver: NSObject, RTCVideoRenderer {
    private let onFrame: @Sendable () -> Void

    init(onFrame: @escaping @Sendable () -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard frame != nil else {
            return
        }
        onFrame()
    }
}

private enum WebRTCReceiverError: LocalizedError {
    case couldNotCreatePeerConnection

    var errorDescription: String? {
        switch self {
        case .couldNotCreatePeerConnection:
            "Could not create WebRTC peer connection"
        }
    }
}

private extension RTCPeerConnection {
    func makeAnswer() async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueFalse,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            answer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: WebRTCReceiverError.couldNotCreatePeerConnection)
                }
            }
        }
    }

    func setLocal(_ description: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func setRemote(_ description: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func add(_ candidate: RTCIceCandidate) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            add(candidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
