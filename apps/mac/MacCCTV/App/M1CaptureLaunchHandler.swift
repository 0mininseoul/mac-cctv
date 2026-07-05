import CCTVKit
import Darwin
import Foundation

enum M1CaptureLaunchHandler {
    static let captureArgument = "--m1-capture"

    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(captureArgument) else {
            return
        }

        Task {
            do {
                let result = try await run(arguments: arguments)
                finish(result, exitCode: 0)
            } catch {
                finish("M1_CAPTURE_FAILED \(error.localizedDescription)", exitCode: 2)
            }
        }
    }

    private static func run(arguments: [String]) async throws -> String {
        let duration = value(after: "--duration", in: arguments).flatMap(TimeInterval.init) ?? 60
        let settings = CaptureSettings.m1Default
        let sessionID = "m1-\(Int(Date().timeIntervalSince1970))"
        let outputDirectory = try outputDirectory(for: sessionID, arguments: arguments)
        writeDiagnostic("M1_CAPTURE_STARTED duration=\(duration) output=\(outputDirectory.path)")

        let engine = try CaptureEngine(outputDirectory: outputDirectory, settings: settings)
        try await engine.start()
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        let chunks = engine.stopAndWaitForChunks()
        let manifestURL = outputDirectory.appendingPathComponent("manifest.json")
        let manifest = CaptureManifest(
            sessionID: sessionID,
            outputDirectory: outputDirectory,
            requestedDuration: duration,
            settings: settings,
            chunks: chunks
        )
        let manifestData = try JSONEncoder.m1Manifest.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        guard !chunks.isEmpty else {
            throw M1CaptureError.noChunksWritten
        }

        return [
            "M1_CAPTURE_OK",
            "duration=\(duration)",
            "chunks=\(chunks.count)",
            "output=\(outputDirectory.path)",
            "manifest=\(manifestURL.path)"
        ].joined(separator: " ")
    }

    private static func outputDirectory(for sessionID: String, arguments: [String]) throws -> URL {
        if let path = value(after: "--output-dir", in: arguments) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        if let path = ProcessInfo.processInfo.environment["M1_CAPTURE_OUTPUT_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier
        ) else {
            throw M1CaptureError.appGroupUnavailable
        }
        return appGroupURL.appendingPathComponent("M1Chunks").appendingPathComponent(sessionID)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func finish(_ line: String, exitCode: Int32) -> Never {
        print(line)
        fflush(stdout)
        if let outputPath = ProcessInfo.processInfo.environment["M1_CAPTURE_RESULT_PATH"] {
            try? line.appending("\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
        }
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier) {
            let resultURL = appGroupURL.appendingPathComponent("m1-capture-result.txt")
            try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
        }
        exit(exitCode)
    }

    private static func writeDiagnostic(_ line: String) {
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier) {
            let resultURL = appGroupURL.appendingPathComponent("m1-capture-result.txt")
            try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
        }
    }
}

private enum M1CaptureError: LocalizedError {
    case appGroupUnavailable
    case noChunksWritten

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "App Group container is unavailable"
        case .noChunksWritten:
            "No MP4 chunks were written"
        }
    }
}

private extension JSONEncoder {
    static var m1Manifest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
