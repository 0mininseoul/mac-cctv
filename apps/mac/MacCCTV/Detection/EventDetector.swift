import AppKit
import CCTVKit
import Foundation
import IOKit
import IOKit.ps

struct DetectedSecurityEvent: Sendable {
    let type: SecurityEventType
    let confidence: Double
}

final class EventDetector {
    var onEvent: (@Sendable (DetectedSecurityEvent) -> Void)?
    var onDiagnostic: (@Sendable (String) -> Void)?
    var onSystemWake: (@Sendable () -> Void)?

    private var inputPollTimer: DispatchSourceTimer?
    private var powerRunLoopSource: CFRunLoopSource?
    private var willSleepObserver: NSObjectProtocol?
    private var didWakeObserver: NSObjectProtocol?
    private var clamshellTimer: DispatchSourceTimer?
    private var lastExternalPowerConnected: Bool?
    private var lastClamshellClosed: Bool?
    private var lastEmittedAt: [SecurityEventType: Date] = [:]
    private var inputActivityTracker = InputActivityTracker()
    private let debounceInterval: TimeInterval = 3

    func start() {
        stop()
        lastExternalPowerConnected = Self.isExternalPowerConnected()
        lastClamshellClosed = Self.isClamshellClosed()
        startInputIdlePolling()
        startPowerMonitoring()
        startLidMonitoring()
        startWakeMonitoring()
    }

    func stop() {
        inputPollTimer?.cancel()
        if let powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerRunLoopSource, .defaultMode)
        }
        if let willSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(willSleepObserver)
        }
        if let didWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(didWakeObserver)
        }
        clamshellTimer?.cancel()

        inputPollTimer = nil
        self.powerRunLoopSource = nil
        self.willSleepObserver = nil
        self.didWakeObserver = nil
        self.clamshellTimer = nil
        lastEmittedAt.removeAll()
    }

    private func startInputIdlePolling() {
        inputActivityTracker = InputActivityTracker()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.pollInputActivity()
        }
        timer.resume()
        inputPollTimer = timer
        onDiagnostic?("M5_INPUT_IDLE_POLL ready")
    }

    private func startPowerMonitoring() {
        guard let source = IOPSNotificationCreateRunLoopSource(
            Self.powerSourceChanged,
            Unmanaged.passUnretained(self).toOpaque()
        )?.takeRetainedValue() else {
            return
        }
        powerRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func startLidMonitoring() {
        willSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.emit(.lidClose, confidence: 0.8)
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.checkClamshellState()
        }
        timer.resume()
        clamshellTimer = timer
    }

    private func startWakeMonitoring() {
        didWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onSystemWake?()
        }
    }

    private func checkPowerState() {
        let connected = Self.isExternalPowerConnected()
        defer { lastExternalPowerConnected = connected }

        if lastExternalPowerConnected == true, connected == false {
            emit(.powerDisconnect, confidence: 1)
        }
    }

    private func checkClamshellState() {
        let closed = Self.isClamshellClosed()
        defer { lastClamshellClosed = closed }

        if lastClamshellClosed == false, closed == true {
            emit(.lidClose, confidence: 1)
        }
    }

    private func pollInputActivity() {
        let idleSeconds = Self.currentInputIdleSeconds()
        guard inputActivityTracker.observe(now: Date(), idleSeconds: idleSeconds) else {
            return
        }
        emit(.inputTouch, confidence: 1)
    }

    private func emit(_ type: SecurityEventType, confidence: Double) {
        let now = Date()
        if let last = lastEmittedAt[type], now.timeIntervalSince(last) < debounceInterval {
            return
        }
        lastEmittedAt[type] = now
        onEvent?(DetectedSecurityEvent(type: type, confidence: confidence))
    }

    private static func isExternalPowerConnected() -> Bool {
        IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() != nil
    }

    private static let powerSourceChanged: IOPowerSourceCallbackType = { context in
        guard let context else {
            return
        }
        let detector = Unmanaged<EventDetector>.fromOpaque(context).takeUnretainedValue()
        detector.checkPowerState()
    }

    private static func currentInputIdleSeconds() -> TimeInterval {
        let idleTimes = inputEventTypes
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
            .filter { $0.isFinite && $0 >= 0 }
        return idleTimes.min() ?? .greatestFiniteMagnitude
    }

    private static let inputEventTypes: [CGEventType] = [
        .keyDown,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel
    ]

    private static func isClamshellClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            return false
        }
        defer { IOObjectRelease(service) }

        let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        return value as? Bool ?? false
    }
}
