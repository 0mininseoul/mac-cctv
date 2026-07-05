import AppKit
import CoreAudio
import SwiftUI

@MainActor
final class SirenController {
    private let volumeController = SystemOutputVolumeController()
    private var originalVolume: Float32?
    private var originalMuteState: UInt32?
    private var warningWindows: [NSWindow] = []
    private var sound: NSSound?

    private(set) var isActive = false

    func start(warningText: String) {
        guard !isActive else {
            return
        }

        isActive = true
        originalVolume = try? volumeController.outputVolume()
        originalMuteState = try? volumeController.outputMute()
        try? volumeController.setOutputMuted(false)
        try? volumeController.setOutputVolume(1)
        startSoundLoop()
        showWarningWindows(warningText: warningText)
    }

    func stop() {
        guard isActive else {
            return
        }

        isActive = false
        sound?.stop()
        sound = nil
        closeWarningWindows()

        if let originalVolume {
            try? volumeController.setOutputVolume(originalVolume)
        }
        if let originalMuteState {
            try? volumeController.setOutputMuted(originalMuteState != 0)
        }
        originalVolume = nil
        originalMuteState = nil
    }

    private func startSoundLoop() {
        let alarmSound = NSSound(named: NSSound.Name("Basso"))
            ?? NSSound(named: NSSound.Name("Sosumi"))
            ?? NSSound(named: NSSound.Name("Submarine"))
        alarmSound?.loops = true
        alarmSound?.volume = 1
        alarmSound?.play()
        sound = alarmSound
    }

    private func showWarningWindows(warningText: String) {
        warningWindows = NSScreen.screens.map { screen in
            let screenFrame = screen.frame
            let window = SirenWarningWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.level = .screenSaver
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .ignoresCycle,
                .stationary,
                .transient
            ]
            window.isReleasedWhenClosed = false
            window.setFrame(screenFrame, display: false)

            let hostingView = NSHostingView(
                rootView: SirenWarningView(warningText: warningText)
                    .frame(width: screenFrame.width, height: screenFrame.height)
            )
            hostingView.frame = NSRect(origin: .zero, size: screenFrame.size)
            hostingView.autoresizingMask = [.width, .height]
            window.contentView = hostingView
            window.orderFrontRegardless()
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeWarningWindows() {
        warningWindows.forEach { $0.close() }
        warningWindows.removeAll()
    }
}

private final class SirenWarningWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private struct SirenWarningView: View {
    let warningText: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 84, weight: .bold))
                    .foregroundStyle(.red)

                Text(warningText)
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SystemOutputVolumeController {
    func outputVolume() throws -> Float32 {
        let deviceID = try defaultOutputDeviceID()
        let readableElements = [mainElement, AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)]
        let values = readableElements.compactMap { element -> Float32? in
            var address = volumeAddress(element: element)
            guard AudioObjectHasProperty(deviceID, &address) else {
                return nil
            }
            return try? readFloat32(deviceID: deviceID, address: &address)
        }
        guard !values.isEmpty else {
            throw SystemOutputVolumeError.volumeUnavailable
        }
        return values.reduce(0, +) / Float32(values.count)
    }

    func setOutputVolume(_ volume: Float32) throws {
        let deviceID = try defaultOutputDeviceID()
        let clampedVolume = min(max(volume, 0), 1)
        var didSetVolume = false

        for element in [mainElement, AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)] {
            var address = volumeAddress(element: element)
            guard AudioObjectHasProperty(deviceID, &address) else {
                continue
            }
            var nextVolume = clampedVolume
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float32>.size),
                &nextVolume
            )
            didSetVolume = didSetVolume || status == noErr
        }

        if !didSetVolume {
            throw SystemOutputVolumeError.volumeUnavailable
        }
    }

    func outputMute() throws -> UInt32? {
        let deviceID = try defaultOutputDeviceID()
        var address = muteAddress()
        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }
        return try readUInt32(deviceID: deviceID, address: &address)
    }

    func setOutputMuted(_ muted: Bool) throws {
        let deviceID = try defaultOutputDeviceID()
        var address = muteAddress()
        guard AudioObjectHasProperty(deviceID, &address) else {
            return
        }
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
        guard status == noErr else {
            throw SystemOutputVolumeError.coreAudio(status)
        }
    }

    private var mainElement: AudioObjectPropertyElement {
        AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    }

    private func defaultOutputDeviceID() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: mainElement
        )
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else {
            throw SystemOutputVolumeError.coreAudio(status)
        }
        return deviceID
    }

    private func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: mainElement
        )
    }

    private func readFloat32(
        deviceID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) throws -> Float32 {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw SystemOutputVolumeError.coreAudio(status)
        }
        return value
    }

    private func readUInt32(
        deviceID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) throws -> UInt32 {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw SystemOutputVolumeError.coreAudio(status)
        }
        return value
    }
}

private enum SystemOutputVolumeError: Error {
    case coreAudio(OSStatus)
    case volumeUnavailable
}
