import AVFoundation
import CCTVKit
import Foundation
import WebRTC

final class BroadcastSession: NSObject, @unchecked Sendable {
    private let sessionID: String
    private let channel: SignalingChannel
    private let diagnostics: @Sendable (String) -> Void
    private let onSirenCommand: @Sendable () -> Void
    private let onDismissEscalation: @Sendable () -> Void
    private let factory: RTCPeerConnectionFactory
    private let videoSource: RTCVideoSource
    private let videoCapturer: RTCVideoCapturer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let receiveIntervalNanoseconds: UInt64 = 200_000_000
    private var peerConnection: RTCPeerConnection?
    private var controlDataChannel: RTCDataChannel?
    private var receiveTask: Task<Void, Never>?
    private var cursor = Date.distantPast
    private var processedSignalIDs = Set<String>()
    private var pendingRemoteIceCandidates: [RTCIceCandidate] = []
    private var hasRemoteDescription = false
    private var ingestedFrameCount = 0

    init(
        sessionID: String,
        channel: SignalingChannel,
        diagnostics: @escaping @Sendable (String) -> Void,
        onSirenCommand: @escaping @Sendable () -> Void,
        onDismissEscalation: @escaping @Sendable () -> Void
    ) {
        self.sessionID = sessionID
        self.channel = channel
        self.diagnostics = diagnostics
        self.onSirenCommand = onSirenCommand
        self.onDismissEscalation = onDismissEscalation
        let factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        let videoSource = factory.videoSource()
        self.factory = factory
        self.videoSource = videoSource
        self.videoCapturer = RTCVideoCapturer(delegate: videoSource)
        super.init()
    }

    func start() async throws {
        videoSource.adaptOutputFormat(toWidth: 1280, height: 720, fps: 24)
        startReceiveLoop()
    }

    /// Creates a fresh peer connection and sends a new offer. Called for the first
    /// viewer of a session and again for every reconnect (`.viewerReady`) — a
    /// once-and-only-once offer at recording start has no way to recover once a
    /// viewer's peer connection is torn down (e.g. backgrounding the app), so every
    /// viewer arrival renegotiates from scratch instead.
    private func negotiate() async throws {
        peerConnection?.close()
        controlDataChannel?.delegate = nil
        hasRemoteDescription = false
        pendingRemoteIceCandidates.removeAll()

        let connection = try makePeerConnection()
        peerConnection = connection
        controlDataChannel = makeControlDataChannel(on: connection)

        let videoTrack = factory.videoTrack(with: videoSource, trackId: "mac-video-\(sessionID)")
        guard connection.add(videoTrack, streamIds: ["mac-cctv-\(sessionID)"]) != nil else {
            throw BroadcastSessionError.couldNotAddVideoTrack
        }

        let offer = try await connection.makeOffer()
        try await connection.setLocal(offer)
        try await send(description: offer, kind: .offer)
        diagnostics("M6_BROADCAST_OFFER_SENT session=\(sessionID)")
    }

    func stop() async {
        receiveTask?.cancel()
        receiveTask = nil
        controlDataChannel?.delegate = nil
        controlDataChannel = nil
        processedSignalIDs.removeAll()
        pendingRemoteIceCandidates.removeAll()
        hasRemoteDescription = false
        peerConnection?.close()
        peerConnection = nil
        diagnostics("M6_BROADCAST_STOPPED session=\(sessionID)")
    }

    func ingest(sampleBuffer: CMSampleBuffer) {
        guard peerConnection != nil,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let timestampSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let timestampNs = Int64(max(0, timestampSeconds) * 1_000_000_000)
        let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let frame = RTCVideoFrame(buffer: rtcBuffer, rotation: ._0, timeStampNs: timestampNs)
        videoCapturer.delegate?.capturer(videoCapturer, didCapture: frame)
        ingestedFrameCount += 1
        if ingestedFrameCount == 1 || ingestedFrameCount.isMultiple(of: 60) {
            diagnostics("M6_BROADCAST_FRAME_INGESTED session=\(sessionID) count=\(ingestedFrameCount)")
        }
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
            throw BroadcastSessionError.couldNotCreatePeerConnection
        }
        return connection
    }

    private func makeControlDataChannel(on connection: RTCPeerConnection) -> RTCDataChannel? {
        let configuration = RTCDataChannelConfiguration()
        configuration.isOrdered = true
        let dataChannel = connection.dataChannel(forLabel: "mac-cctv-control", configuration: configuration)
        dataChannel?.delegate = self
        diagnostics("M7_SIREN_DATA_CHANNEL_CREATED session=\(sessionID) available=\(dataChannel != nil)")
        return dataChannel
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.receiveOnce()
                do {
                    try await Task.sleep(nanoseconds: self?.receiveIntervalNanoseconds ?? 200_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func receiveOnce() async {
        do {
            let messages = try await channel.receive(after: cursor)
            let newMessages = messages.filter { !processedSignalIDs.contains($0.id) }
            if !newMessages.isEmpty {
                diagnostics("M6_BROADCAST_SIGNAL_BATCH session=\(sessionID) count=\(newMessages.count) hasRemoteDescription=\(hasRemoteDescription)")
            }

            for message in prioritize(newMessages) {
                do {
                    try await handle(message)
                    processedSignalIDs.insert(message.id)
                } catch {
                    diagnostics("M6_BROADCAST_SIGNAL_HANDLE_FAILED session=\(sessionID) kind=\(message.kind.rawValue) error=\(error.localizedDescription)")
                }
            }

            if hasRemoteDescription {
                cursor = messages.map(\.createdAt).max() ?? cursor
            }
        } catch {
            diagnostics("M6_BROADCAST_SIGNAL_RECEIVE_FAILED session=\(sessionID) error=\(error.localizedDescription)")
        }
    }

    private func prioritize(_ messages: [SignalMessage]) -> [SignalMessage] {
        messages.sorted { first, second in
            let firstPriority = signalPriority(first.kind)
            let secondPriority = signalPriority(second.kind)
            if firstPriority == secondPriority {
                return first.createdAt < second.createdAt
            }
            return firstPriority < secondPriority
        }
    }

    private func signalPriority(_ kind: SignalKind) -> Int {
        switch kind {
        case .sirenCommand, .dismissEscalation:
            0
        case .viewerReady:
            1
        case .answer:
            2
        case .ice:
            3
        case .offer:
            4
        }
    }

    private func handle(_ message: SignalMessage) async throws {
        if message.kind == .sirenCommand {
            let age = Date().timeIntervalSince(message.createdAt)
            diagnostics("M7_SIREN_COMMAND_RECEIVED session=\(sessionID) sender=\(message.sender.rawValue) age=\(String(format: "%.2f", age))")
            onSirenCommand()
            return
        }

        if message.kind == .dismissEscalation {
            let age = Date().timeIntervalSince(message.createdAt)
            diagnostics("M10_DISMISS_ESCALATION_RECEIVED session=\(sessionID) sender=\(message.sender.rawValue) age=\(String(format: "%.2f", age))")
            onDismissEscalation()
            return
        }

        if message.kind == .viewerReady {
            diagnostics("M6_BROADCAST_VIEWER_READY session=\(sessionID)")
            do {
                try await negotiate()
            } catch {
                diagnostics("M6_BROADCAST_NEGOTIATE_FAILED session=\(sessionID) error=\(error.localizedDescription)")
            }
            return
        }

        guard let peerConnection else {
            return
        }

        switch message.kind {
        case .answer:
            guard peerConnection.signalingState == .haveLocalOffer else {
                diagnostics(
                    "M6_BROADCAST_ANSWER_IGNORED session=\(sessionID) state=\(peerConnection.signalingState.rawValue)"
                )
                return
            }
            let payload = try decoder.decode(SessionDescriptionSignalPayload.self, from: Data(message.payload.utf8))
            let description = RTCSessionDescription(
                type: RTCSessionDescription.type(for: payload.type),
                sdp: payload.sdp
            )
            try await peerConnection.setRemote(description)
            hasRemoteDescription = true
            try await flushPendingRemoteIceCandidates(on: peerConnection)
            diagnostics("M6_BROADCAST_ANSWER_RECEIVED session=\(sessionID)")
        case .ice:
            let payload = try decoder.decode(IceCandidateSignalPayload.self, from: Data(message.payload.utf8))
            let candidate = RTCIceCandidate(
                sdp: payload.sdp,
                sdpMLineIndex: payload.sdpMLineIndex,
                sdpMid: payload.sdpMid
            )
            guard hasRemoteDescription else {
                pendingRemoteIceCandidates.append(candidate)
                diagnostics("M6_BROADCAST_REMOTE_ICE_QUEUED session=\(sessionID) \(candidateSummary(payload.sdp)) mid=\(payload.sdpMid ?? "nil") index=\(payload.sdpMLineIndex)")
                return
            }
            try await peerConnection.add(candidate)
            diagnostics("M6_BROADCAST_REMOTE_ICE_ADDED session=\(sessionID) \(candidateSummary(payload.sdp)) mid=\(payload.sdpMid ?? "nil") index=\(payload.sdpMLineIndex)")
        case .offer, .sirenCommand, .viewerReady, .dismissEscalation:
            return
        }
    }

    private func flushPendingRemoteIceCandidates(on peerConnection: RTCPeerConnection) async throws {
        guard !pendingRemoteIceCandidates.isEmpty else {
            return
        }

        let queuedCandidates = pendingRemoteIceCandidates
        pendingRemoteIceCandidates.removeAll()
        for candidate in queuedCandidates {
            try await peerConnection.add(candidate)
        }
        diagnostics("M6_BROADCAST_REMOTE_ICE_FLUSHED session=\(sessionID) count=\(queuedCandidates.count)")
    }

    private func send(description: RTCSessionDescription, kind: SignalKind) async throws {
        let payload = SessionDescriptionSignalPayload(
            type: RTCSessionDescription.string(for: description.type),
            sdp: description.sdp
        )
        let data = try encoder.encode(payload)
        try await channel.send(
            SignalMessage(
                id: "\(sessionID)-mac-\(kind.rawValue)-\(UUID().uuidString)",
                sessionID: sessionID,
                kind: kind,
                payload: String(decoding: data, as: UTF8.self),
                sender: .mac,
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
                    id: "\(sessionID)-mac-ice-\(UUID().uuidString)",
                    sessionID: sessionID,
                    kind: .ice,
                    payload: String(decoding: data, as: UTF8.self),
                    sender: .mac,
                    createdAt: Date()
                )
            )
            diagnostics("M6_BROADCAST_LOCAL_ICE_SENT session=\(sessionID) \(candidateSummary(candidate.sdp)) mid=\(candidate.sdpMid ?? "nil") index=\(candidate.sdpMLineIndex)")
        } catch {
            diagnostics("M6_BROADCAST_ICE_SEND_FAILED session=\(sessionID) error=\(error.localizedDescription)")
        }
    }
}

extension BroadcastSession: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        diagnostics("M6_BROADCAST_ICE_STATE session=\(sessionID) state=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        diagnostics("M6_BROADCAST_ICE_GATHERING_STATE session=\(sessionID) state=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { [weak self] in
            await self?.send(candidate: candidate)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        controlDataChannel = dataChannel
        dataChannel.delegate = self
        diagnostics("M7_SIREN_DATA_CHANNEL_OPENED session=\(sessionID) label=\(dataChannel.label)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        diagnostics("M6_BROADCAST_CONNECTION_STATE session=\(sessionID) state=\(newState.rawValue)")
    }
}

extension BroadcastSession: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        diagnostics("M7_SIREN_DATA_CHANNEL_STATE session=\(sessionID) state=\(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard !buffer.isBinary,
              let message = String(data: buffer.data, encoding: .utf8),
              message.hasPrefix("sirenCommand") else {
            return
        }

        let age = dataChannelCommandAge(message)
        diagnostics("M7_SIREN_DATA_CHANNEL_RECEIVED session=\(sessionID) age=\(String(format: "%.2f", age))")
        onSirenCommand()
    }

    private func dataChannelCommandAge(_ message: String) -> TimeInterval {
        let parts = message.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let sentAt = TimeInterval(parts[1]) else {
            return -1
        }
        return Date().timeIntervalSince1970 - sentAt
    }
}

private func candidateSummary(_ sdp: String) -> String {
    let parts = sdp.split(separator: " ").map(String.init)
    let type = value(after: "typ", in: parts) ?? "unknown"
    let protocolName = parts.count > 2 ? parts[2].lowercased() : "unknown"
    let tcpType = value(after: "tcptype", in: parts)
    let networkID = value(after: "network-id", in: parts)
    let tcpSuffix = tcpType.map { " tcpType=\($0)" } ?? ""
    let networkSuffix = networkID.map { " network=\($0)" } ?? ""
    return "candidateType=\(type) protocol=\(protocolName)\(tcpSuffix)\(networkSuffix)"
}

private func value(after marker: String, in parts: [String]) -> String? {
    guard let index = parts.firstIndex(of: marker),
          parts.indices.contains(index + 1) else {
        return nil
    }
    return parts[index + 1]
}

private enum BroadcastSessionError: LocalizedError {
    case couldNotCreatePeerConnection
    case couldNotAddVideoTrack

    var errorDescription: String? {
        switch self {
        case .couldNotCreatePeerConnection:
            "Could not create WebRTC peer connection"
        case .couldNotAddVideoTrack:
            "Could not add WebRTC video track"
        }
    }
}

private extension RTCPeerConnection {
    func makeOffer() async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueFalse,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse
            ],
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            offer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: BroadcastSessionError.couldNotCreatePeerConnection)
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
