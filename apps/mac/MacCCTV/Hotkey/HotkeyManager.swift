import Carbon
import Foundation

struct HotkeyShortcut: Hashable, Identifiable, Sendable {
    let id: String
    let keyCode: UInt32
    let modifiers: UInt32
    let display: String

    static let controlCommandC = HotkeyShortcut(
        id: "control-command-c",
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(cmdKey | controlKey),
        display: "⌃⌘C"
    )

    static let controlCommandM = HotkeyShortcut(
        id: "control-command-m",
        keyCode: UInt32(kVK_ANSI_M),
        modifiers: UInt32(cmdKey | controlKey),
        display: "⌃⌘M"
    )

    static let controlCommandV = HotkeyShortcut(
        id: "control-command-v",
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | controlKey),
        display: "⌃⌘V"
    )

    static let all: [HotkeyShortcut] = [
        .controlCommandC,
        .controlCommandM,
        .controlCommandV
    ]
}

enum HotkeyManagerError: Error, LocalizedError {
    case cannotInstallHandler(OSStatus)
    case cannotRegister(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .cannotInstallHandler(status):
            "Could not install hotkey handler: \(status)"
        case let .cannotRegister(status):
            "Could not register hotkey: \(status)"
        }
    }
}

final class HotkeyManager {
    var onPressed: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?
    private var registeredShortcut: HotkeyShortcut?

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(_ shortcut: HotkeyShortcut) throws {
        try installHandlerIfNeeded()
        unregister()

        let hotkeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let hotkeyRef else {
            throw HotkeyManagerError.cannotRegister(status)
        }

        self.hotkeyRef = hotkeyRef
        self.registeredShortcut = shortcut
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
        }
        hotkeyRef = nil
        registeredShortcut = nil
    }

    private func installHandlerIfNeeded() throws {
        guard eventHandler == nil else {
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotkeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                guard parameterStatus == noErr, hotkeyID.signature == HotkeyManager.signature else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onPressed?()
                }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            throw HotkeyManagerError.cannotInstallHandler(status)
        }
    }

    private static let signature = fourCharCode("MCTV")

    private static func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}
