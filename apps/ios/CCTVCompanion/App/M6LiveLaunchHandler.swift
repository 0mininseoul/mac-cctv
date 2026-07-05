import CCTVKit
import Darwin
import Foundation

enum M6LiveLaunchHandler {
    static let watchLatestArgument = "--m6-watch-latest"

    static func runIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(watchLatestArgument) else {
            return false
        }

        writeDiagnostic("M6_WEBRTC_STARTED \(arguments.joined(separator: " "))")
        Task {
            do {
                let result = try await withTimeout(seconds: 30) {
                    try await run(arguments: arguments)
                }
                finish(result, exitCode: 0)
            } catch {
                finish("M6_WEBRTC_FAILED \(error.localizedDescription)", exitCode: 2)
            }
        }
        return true
    }

    @MainActor
    private static func run(arguments: [String]) async throws -> String {
        let store = CloudKitStore()
        let session: SurveillanceSession

        if let sessionID = value(after: "--session-id", in: arguments) {
            session = try await store.fetchSession(id: sessionID)
        } else if let latest = try await store.fetchSessions(limit: 20).first(where: { $0.status == .recording }) {
            session = latest
        } else {
            throw M6LiveError.noRecordingSession
        }

        let expectFallback = arguments.contains("--expect-fallback")
        let shouldSendSirenCommand = arguments.contains("--send-siren-command")
        let receiver = WebRTCReceiver(
            session: session,
            diagnostics: { line in
                print(line)
                fflush(stdout)
            }
        )
        receiver.start()
        defer {
            receiver.stop()
        }

        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(20)
        while Date() < deadline {
            switch receiver.viewingMode {
            case .realtime:
                if shouldSendSirenCommand {
                    let sent = await sendRealtimeSirenCommand(receiver: receiver)
                    return [
                        "M7_SIREN_REALTIME_COMMAND_SENT",
                        "session=\(session.id)",
                        "sent=\(sent)",
                        "elapsed=\(String(format: "%.1f", Date().timeIntervalSince(startedAt)))"
                    ].joined(separator: " ")
                }

                return [
                    "M6_WEBRTC_OK",
                    "session=\(session.id)",
                    "mode=realtime",
                    "elapsed=\(String(format: "%.1f", Date().timeIntervalSince(startedAt)))"
                ].joined(separator: " ")
            case let .delayedFallback(reason):
                if expectFallback {
                    return [
                        "M6_WEBRTC_FALLBACK_OK",
                        "session=\(session.id)",
                        "reason=\(reason)",
                        "elapsed=\(String(format: "%.1f", Date().timeIntervalSince(startedAt)))"
                    ].joined(separator: " ")
                }
                throw M6LiveError.fellBack(reason)
            case .connecting:
                print(
                    "M6_WEBRTC_WAIT session=\(session.id) mode=connecting status=\"\(receiver.statusText)\" elapsed=\(String(format: "%.1f", Date().timeIntervalSince(startedAt)))"
                )
                fflush(stdout)
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        throw M6LiveError.timeout
    }

    @MainActor
    private static func sendRealtimeSirenCommand(receiver: WebRTCReceiver) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if receiver.sendSirenCommandOverRealtimeChannel() {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw M6LiveError.timeout
            }
            guard let result = try await group.next() else {
                throw M6LiveError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private static func finish(_ line: String, exitCode: Int32) -> Never {
        print(line)
        fflush(stdout)
        writeDiagnostic(line)
        exit(exitCode)
    }

    private static func writeDiagnostic(_ line: String) {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier
        ) else {
            return
        }
        let resultURL = appGroupURL.appendingPathComponent("m6-result.txt")
        try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
    }

    private enum M6LiveError: LocalizedError {
        case noRecordingSession
        case fellBack(LiveFallbackReason)
        case timeout

        var errorDescription: String? {
            switch self {
            case .noRecordingSession:
                "No recording session is available for M6 WebRTC verification"
            case let .fellBack(reason):
                "WebRTC fell back to delayed live: \(reason)"
            case .timeout:
                "Timed out waiting for M6 WebRTC verification"
            }
        }
    }
}
