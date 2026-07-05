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

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var powerRunLoopSource: CFRunLoopSource?
    private var willSleepObserver: NSObjectProtocol?
    private var clamshellTimer: DispatchSourceTimer?
    private var lastExternalPowerConnected: Bool?
    private var lastClamshellClosed: Bool?
    private var lastEmittedAt: [SecurityEventType: Date] = [:]
    private let debounceInterval: TimeInterval = 3

    func start() {
        stop()
        lastExternalPowerConnected = Self.isExternalPowerConnected()
        lastClamshellClosed = Self.isClamshellClosed()
        startInputMonitoring()
        startPowerMonitoring()
        startLidMonitoring()
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        if let powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerRunLoopSource, .defaultMode)
        }
        if let willSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(willSleepObserver)
        }
        clamshellTimer?.cancel()

        globalMonitor = nil
        localMonitor = nil
        self.eventTap = nil
        self.eventTapRunLoopSource = nil
        self.powerRunLoopSource = nil
        self.willSleepObserver = nil
        self.clamshellTimer = nil
        lastEmittedAt.removeAll()
    }

    private func startInputMonitoring() {
        let mask = Self.inputEventMask
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.emit(.inputTouch, confidence: 1)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.emit(.inputTouch, confidence: 1)
            return event
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.inputCGEventMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        self.eventTapRunLoopSource = runLoopSource
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

    private func emit(_ type: SecurityEventType, confidence: Double) {
        let now = Date()
        if let last = lastEmittedAt[type], now.timeIntervalSince(last) < debounceInterval {
            return
        }
        lastEmittedAt[type] = now
        onEvent?(DetectedSecurityEvent(type: type, confidence: confidence))
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, _, event, userInfo in
        if let userInfo {
            let detector = Unmanaged<EventDetector>.fromOpaque(userInfo).takeUnretainedValue()
            detector.emit(.inputTouch, confidence: 1)
        }
        return Unmanaged.passUnretained(event)
    }

    private static let powerSourceChanged: IOPowerSourceCallbackType = { context in
        guard let context else {
            return
        }
        let detector = Unmanaged<EventDetector>.fromOpaque(context).takeUnretainedValue()
        detector.checkPowerState()
    }

    private static var inputEventMask: NSEvent.EventTypeMask {
        [
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
    }

    private static var inputCGEventMask: CGEventMask {
        [
            CGEventType.keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel
        ].reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }

    private static func isExternalPowerConnected() -> Bool {
        IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() != nil
    }

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
