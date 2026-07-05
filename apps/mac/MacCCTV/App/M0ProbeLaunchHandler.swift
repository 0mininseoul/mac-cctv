import CCTVKit
import Darwin
import Foundation

enum M0ProbeLaunchHandler {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(M0ProbeCommand.writeArgument) || arguments.contains(M0ProbeCommand.readArgument) else {
            return
        }

        writeDiagnostic("M0_PROBE_STARTED \(arguments.joined(separator: " "))")
        let deviceName = Host.current().localizedName ?? "Mac"
        Task {
            do {
                let commandResult = try await withTimeout(seconds: 20) {
                    try await M0ProbeCommand.runIfRequested(
                        arguments: arguments,
                        source: .mac,
                        deviceName: deviceName
                    )
                }
                if let result = commandResult {
                    finish(result, exitCode: 0)
                }
                finish("M0_PROBE_NOOP", exitCode: 0)
            } catch {
                finish("M0_PROBE_FAILED \(error.localizedDescription)", exitCode: 2)
            }
        }
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
                throw TimeoutError()
            }
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }

    private static func finish(_ line: String, exitCode: Int32) -> Never {
        print(line)
        fflush(stdout)
        if let outputPath = ProcessInfo.processInfo.environment["M0_PROBE_OUTPUT_PATH"] {
            try? line.appending("\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
        }
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier) {
            let resultURL = appGroupURL.appendingPathComponent("m0-probe-result.txt")
            try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
        }
        exit(exitCode)
    }

    private static func writeDiagnostic(_ line: String) {
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier) {
            let resultURL = appGroupURL.appendingPathComponent("m0-probe-result.txt")
            try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
        }
    }

    private struct TimeoutError: LocalizedError {
        var errorDescription: String? {
            "Timed out waiting for CloudKit probe"
        }
    }
}
