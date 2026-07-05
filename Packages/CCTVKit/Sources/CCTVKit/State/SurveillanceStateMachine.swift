import Foundation

public enum SurveillanceState: Equatable, Sendable {
    case idle
    case armed(startedAt: Date)
    case siren(startedAt: Date, triggeredAt: Date)
}

public enum SurveillanceStateEvent: Equatable, Sendable {
    case arm(startedAt: Date)
    case disarm(endedAt: Date)
    case triggerSiren(triggeredAt: Date)
    case silenceSiren(silencedAt: Date)
}

public enum SurveillanceStateTransitionError: Error, Equatable, Sendable {
    case illegalTransition(from: SurveillanceState, event: SurveillanceStateEvent)
}

public struct SurveillanceStateMachine: Equatable, Sendable {
    public private(set) var state: SurveillanceState

    public init(state: SurveillanceState = .idle) {
        self.state = state
    }

    public mutating func apply(_ event: SurveillanceStateEvent) throws {
        switch (state, event) {
        case (.idle, let .arm(startedAt)):
            state = .armed(startedAt: startedAt)
        case (.armed, .disarm):
            state = .idle
        case (let .armed(startedAt), let .triggerSiren(triggeredAt)):
            state = .siren(startedAt: startedAt, triggeredAt: triggeredAt)
        case (let .siren(startedAt, _), .silenceSiren):
            state = .armed(startedAt: startedAt)
        case (.siren, .disarm):
            state = .idle
        default:
            throw SurveillanceStateTransitionError.illegalTransition(from: state, event: event)
        }
    }
}
