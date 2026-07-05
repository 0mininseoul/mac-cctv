import AVFoundation
import Foundation

enum CaptureEngineError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case cannotAddCameraInput
    case cannotAddVideoOutput

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            "Camera permission was denied"
        case .cameraUnavailable:
            "No camera device is available"
        case .cannotAddCameraInput:
            "The camera input could not be added to the capture session"
        case .cannotAddVideoOutput:
            "The video output could not be added to the capture session"
        }
    }
}

final class CaptureEngine: NSObject, @unchecked Sendable {
    private let settings: CaptureSettings
    private let outputDirectory: URL
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "com.youngminpark.maccctv.capture")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let writer: ChunkWriter
    private var isConfigured = false

    init(outputDirectory: URL, settings: CaptureSettings = .m1Default) throws {
        self.outputDirectory = outputDirectory
        self.settings = settings
        self.writer = try ChunkWriter(outputDirectory: outputDirectory, settings: settings)
        super.init()
    }

    func start() async throws {
        try await requestCameraAccess()
        try configureIfNeeded()
        await withCheckedContinuation { continuation in
            captureQueue.async {
                self.session.startRunning()
                continuation.resume()
            }
        }
    }

    func stopAndWaitForChunks(timeout: TimeInterval = 15) -> [CaptureChunk] {
        captureQueue.sync {
            if session.isRunning {
                session.stopRunning()
            }
            writer.finishCurrentChunk()
        }
        return writer.waitForFinishedChunks(timeout: timeout)
    }

    func finishedChunksSnapshot() -> [CaptureChunk] {
        writer.finishedChunksSnapshot()
    }

    private func requestCameraAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                return
            }
            throw CaptureEngineError.cameraPermissionDenied
        case .denied, .restricted:
            throw CaptureEngineError.cameraPermissionDenied
        @unknown default:
            throw CaptureEngineError.cameraPermissionDenied
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else {
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video) else {
            throw CaptureEngineError.cameraUnavailable
        }

        let cameraInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(cameraInput) else {
            throw CaptureEngineError.cannotAddCameraInput
        }
        session.addInput(cameraInput)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(videoOutput) else {
            throw CaptureEngineError.cannotAddVideoOutput
        }
        session.addOutput(videoOutput)
        isConfigured = true
    }
}

extension CaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        writer.append(sampleBuffer)
    }
}
