import AVFoundation
import CCTVKit
import Foundation
import WebRTC

final class BroadcastSession: NSObject, @unchecked Sendable {
    private let sessionID: String
    private let channel: SignalingChannel
    private let diagnostics: @Sendable (String) -> Void
    private let factory: RTCPeerConnectionFactory
    private let videoSource: RTCVideoSource
    private let videoCapturer: RTCVideoCapturer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var peerConnection: RTCPeerConnection?
    private var receiveTask: Task<Void, Never>?
    private var cursor = Date.distantPast
    private var ingestedFrameCount = 0

    init(
        sessionID: String,
        channel: SignalingChannel,
        diagnostics: @escaping @Sendable (String) -> Void
    ) {
        self.sessionID = sessionID
        self.channel = channel
        self.diagnostics = diagnostics
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
        let connection = try makePeerConnection()
        peerConnection = connection

        videoSource.adaptOutputFormat(toWidth: 1280, height: 720, fps: 24)
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "mac-video-\(sessionID)")
        guard connection.add(videoTrack, streamIds: ["mac-cctv-\(sessionID)"]) != nil else {
            throw BroadcastSessionError.couldNotAddVideoTrack
        }

        let offer = try await connection.makeOffer()
        try await connection.setLocal(offer)
        try await send(description: offer, kind: .offer)
        diagnostics("M6_BROADCAST_OFFER_SENT session=\(sessionID)")
        startReceiveLoop()
    }

    func stop() async {
        receiveTask?.cancel()
        receiveTask = nil
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

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
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

    private func receiveOnce() async {
        do {
            let messages = try await channel.receive(after: cursor)
            cursor = messages.map(\.createdAt).max() ?? cursor
            for message in messages {
                try await handle(message)
            }
        } catch {
            diagnostics("M6_BROADCAST_SIGNAL_RECEIVE_FAILED session=\(sessionID) error=\(error.localizedDescription)")
        }
    }

    private func handle(_ message: SignalMessage) async throws {
        guard let peerConnection else {
            return
        }

        switch message.kind {
        case .answer:
            let payload = try decoder.decode(SessionDescriptionSignalPayload.self, from: Data(message.payload.utf8))
            let description = RTCSessionDescription(
                type: RTCSessionDescription.type(for: payload.type),
                sdp: payload.sdp
            )
            try await peerConnection.setRemote(description)
            diagnostics("M6_BROADCAST_ANSWER_RECEIVED session=\(sessionID)")
        case .ice:
            let payload = try decoder.decode(IceCandidateSignalPayload.self, from: Data(message.payload.utf8))
            let candidate = RTCIceCandidate(
                sdp: payload.sdp,
                sdpMLineIndex: payload.sdpMLineIndex,
                sdpMid: payload.sdpMid
            )
            try await peerConnection.add(candidate)
            diagnostics("M6_BROADCAST_REMOTE_ICE_ADDED session=\(sessionID) \(candidateSummary(payload.sdp)) mid=\(payload.sdpMid ?? "nil") index=\(payload.sdpMLineIndex)")
        case .offer, .sirenCommand:
            return
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

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        diagnostics("M6_BROADCAST_CONNECTION_STATE session=\(sessionID) state=\(newState.rawValue)")
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
