import Foundation
import Network

/// Answers whether the device is currently on an unmetered connection, so background
/// prefetch never spends the user's cellular data allowance.
enum Reachability {
    /// Resolves `true` only on a satisfied, non-expensive, non-constrained path
    /// (Wi-Fi / wired / not a Low Data Mode or Personal Hotspot link). Resolves
    /// `false` if that can't be determined within `timeout`.
    static func isOnUnmeteredConnection(timeout: TimeInterval = 3) async -> Bool {
        /// Bundles the one-shot completion state so the path callback and the timeout
        /// can race safely; whichever fires first resolves the continuation once.
        final class Resolver: @unchecked Sendable {
            let monitor = NWPathMonitor()
            private let lock = NSLock()
            private var finished = false
            private var continuation: CheckedContinuation<Bool, Never>?

            func attach(_ continuation: CheckedContinuation<Bool, Never>) {
                self.continuation = continuation
            }

            func finish(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else {
                    return
                }
                finished = true
                monitor.cancel()
                continuation?.resume(returning: value)
                continuation = nil
            }
        }

        let resolver = Resolver()
        let queue = DispatchQueue(label: "com.youngminpark.maccctv.reachability")
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            resolver.attach(continuation)
            resolver.monitor.pathUpdateHandler = { path in
                resolver.finish(path.status == .satisfied && !path.isExpensive && !path.isConstrained)
            }
            resolver.monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                resolver.finish(false)
            }
        }
    }
}
