import Foundation

public enum AutoSirenDecision: Equatable, Sendable {
    case trigger
    case notifyOnly
}

public struct AutoSirenEvidence: Equatable, Sendable {
    public var type: SecurityEventType
    public var occurredAt: Date
    public var confidence: Double

    public init(type: SecurityEventType, occurredAt: Date, confidence: Double) {
        self.type = type
        self.occurredAt = occurredAt
        self.confidence = confidence
    }
}

public struct AutoSirenTriggerPolicy: Equatable, Sendable {
    public var requiredDeviceMotionDuration: TimeInterval
    public var maxDeviceMotionSampleGap: TimeInterval
    public var inputTouchWindow: TimeInterval
    public var powerDisconnectWindow: TimeInterval
    public var armGracePeriod: TimeInterval
    public var minimumDeviceMotionConfidence: Double

    public init(
        requiredDeviceMotionDuration: TimeInterval = 3,
        maxDeviceMotionSampleGap: TimeInterval = 1.25,
        inputTouchWindow: TimeInterval = 10,
        powerDisconnectWindow: TimeInterval = 30,
        armGracePeriod: TimeInterval = 30,
        minimumDeviceMotionConfidence: Double = 0.72
    ) {
        self.requiredDeviceMotionDuration = requiredDeviceMotionDuration
        self.maxDeviceMotionSampleGap = maxDeviceMotionSampleGap
        self.inputTouchWindow = inputTouchWindow
        self.powerDisconnectWindow = powerDisconnectWindow
        self.armGracePeriod = armGracePeriod
        self.minimumDeviceMotionConfidence = minimumDeviceMotionConfidence
    }

    public func decision(
        armedAt: Date,
        now: Date,
        evidence: [AutoSirenEvidence]
    ) -> AutoSirenDecision {
        guard now.timeIntervalSince(armedAt) >= armGracePeriod else {
            return .notifyOnly
        }
        guard hasRecentReinforcingSignal(now: now, evidence: evidence) else {
            return .notifyOnly
        }
        guard continuousDeviceMotionDuration(now: now, evidence: evidence) >= requiredDeviceMotionDuration else {
            return .notifyOnly
        }
        return .trigger
    }

    private func hasRecentReinforcingSignal(now: Date, evidence: [AutoSirenEvidence]) -> Bool {
        evidence.contains { item in
            let age = now.timeIntervalSince(item.occurredAt)
            switch item.type {
            case .inputTouch:
                return age >= 0 && age <= inputTouchWindow
            case .powerDisconnect:
                return age >= 0 && age <= powerDisconnectWindow
            case .lidClose, .personMotion, .deviceMotion, .sirenAuto, .sirenManual:
                return false
            }
        }
    }

    private func continuousDeviceMotionDuration(now: Date, evidence: [AutoSirenEvidence]) -> TimeInterval {
        let samples = evidence
            .filter { item in
                item.type == .deviceMotion &&
                    item.confidence >= minimumDeviceMotionConfidence &&
                    item.occurredAt <= now
            }
            .map(\.occurredAt)
            .sorted(by: >)

        guard let latest = samples.first,
              now.timeIntervalSince(latest) <= maxDeviceMotionSampleGap else {
            return 0
        }

        var earliest = latest
        var previous = latest
        for sample in samples.dropFirst() {
            guard previous.timeIntervalSince(sample) <= maxDeviceMotionSampleGap else {
                break
            }
            earliest = sample
            previous = sample
        }

        return latest.timeIntervalSince(earliest)
    }
}
