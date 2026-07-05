import Foundation
import IOKit.pwr_mgt

enum SleepBlockerError: Error, LocalizedError {
    case cannotCreateAssertion(IOReturn)

    var errorDescription: String? {
        switch self {
        case let .cannotCreateAssertion(status):
            "Could not prevent system sleep: \(status)"
        }
    }
}

final class SleepBlocker {
    private var assertionID = IOPMAssertionID(0)
    private var isActive = false

    func start() throws {
        guard !isActive else {
            return
        }

        var assertionID = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Mac CCTV surveillance" as CFString,
            &assertionID
        )

        guard status == kIOReturnSuccess else {
            throw SleepBlockerError.cannotCreateAssertion(status)
        }

        self.assertionID = assertionID
        isActive = true
    }

    func stop() {
        guard isActive else {
            return
        }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }
}
