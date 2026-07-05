import CCTVKit
import Darwin
import Foundation

enum M5EventPollLaunchHandler {
    static let pollArgument = "--m5-poll-events"

    @discardableResult
    static func runIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(pollArgument) else {
            return false
        }

        writeDiagnostic("M5_EVENT_POLL_STARTED \(arguments.joined(separator: " "))")
        Task {
            do {
                let result = try await withTimeout(seconds: 25) {
                    try await run(arguments: arguments)
                }
                finish(result, exitCode: 0)
            } catch {
                finish("M5_EVENT_POLL_FAILED \(error.localizedDescription)", exitCode: 2)
            }
        }
        return true
    }

    private static func run(arguments: [String]) async throws -> String {
        let store = CloudKitStore()
        try? await store.ensureEventSubscription()

        guard let sessionID = value(after: "--session-id", in: arguments) else {
            throw M5EventPollError.missingSessionID
        }
        let requestedType = value(after: "--event-type", in: arguments).flatMap(SecurityEventType.init(rawValue:))
        let since = value(after: "--since", in: arguments)
            .flatMap(Double.init)
            .map(Date.init(timeIntervalSince1970:))

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let events = try await store.fetchEvents(sessionID: sessionID, after: since, limit: 200)
            if let event = events.first(where: { event in
                guard let requestedType else {
                    return true
                }
                return event.type == requestedType
            }) {
                let latency = Date().timeIntervalSince(event.occurredAt)
                return [
                    "M5_EVENT_RECEIVED",
                    "session=\(event.sessionID)",
                    "type=\(event.type.rawValue)",
                    "events=\(events.count)",
                    "confidence=\(String(format: "%.2f", event.confidence))",
                    "occurredAt=\(Int(event.occurredAt.timeIntervalSince1970))",
                    "latency=\(String(format: "%.2f", latency))"
                ].joined(separator: " ")
            }

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        throw M5EventPollError.timeout
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
                throw M5EventPollError.timeout
            }
            guard let result = try await group.next() else {
                throw M5EventPollError.timeout
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
        let resultURL = appGroupURL.appendingPathComponent("m5-event-result.txt")
        try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
    }

    private enum M5EventPollError: LocalizedError {
        case missingSessionID
        case timeout

        var errorDescription: String? {
            switch self {
            case .missingSessionID:
                "Missing --session-id"
            case .timeout:
                "Timed out waiting for a matching event"
            }
        }
    }
}
