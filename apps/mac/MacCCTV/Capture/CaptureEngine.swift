import AVFoundation
import CCTVKit
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
    private let motionClassifier = MotionClassifier()
    private var isConfigured = false
    private var previousMotionFrame: MotionFrame?
    private var lastMotionSampleSeconds = -Double.greatestFiniteMagnitude

    var onMotionClassification: (@Sendable (MotionClassification) -> Void)?
    var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?

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

    func flushCurrentChunk(timeout: TimeInterval = 5) -> [CaptureChunk] {
        captureQueue.sync {
            writer.finishCurrentChunk()
        }
        return writer.waitForFinishedChunks(timeout: timeout)
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
        onVideoSampleBuffer?(sampleBuffer)
        classifyMotionIfNeeded(sampleBuffer)
    }

    private func classifyMotionIfNeeded(_ sampleBuffer: CMSampleBuffer) {
        let presentationSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard presentationSeconds - lastMotionSampleSeconds >= 1 else {
            return
        }
        lastMotionSampleSeconds = presentationSeconds

        guard let currentFrame = Self.makeMotionFrame(from: sampleBuffer) else {
            return
        }
        defer { previousMotionFrame = currentFrame }

        guard let previousMotionFrame else {
            return
        }

        guard let classification = try? motionClassifier.classify(previous: previousMotionFrame, current: currentFrame),
              classification != .noMotion else {
            return
        }
        onMotionClassification?(classification)
    }

    private static func makeMotionFrame(from sampleBuffer: CMSampleBuffer, sampleSize: Int = 64) -> MotionFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let planeIndex = CVPixelBufferGetPlaneCount(pixelBuffer) > 0 ? 0 : nil
        let sourceWidth: Int
        let sourceHeight: Int
        let rowBytes: Int
        let baseAddress: UnsafeMutableRawPointer?

        if let planeIndex {
            sourceWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
            sourceHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
            rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex)
            baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex)
        } else {
            sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
            sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
            rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        }

        guard sourceWidth > 0, sourceHeight > 0, let baseAddress else {
            return nil
        }

        let source = baseAddress.assumingMemoryBound(to: UInt8.self)
        var luma = Array(repeating: UInt8(0), count: sampleSize * sampleSize)
        for y in 0..<sampleSize {
            let sourceY = y * sourceHeight / sampleSize
            for x in 0..<sampleSize {
                let sourceX = x * sourceWidth / sampleSize
                luma[(y * sampleSize) + x] = source[(sourceY * rowBytes) + sourceX]
            }
        }

        return MotionFrame(width: sampleSize, height: sampleSize, luma: luma)
    }
}
