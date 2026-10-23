// MicFixer — keeps the Mac's default audio input off Bluetooth headsets (e.g. AirPods)
// so macOS doesn't drop the output to low-quality "headset" mode.

import AppKit
import CoreAudio
import ServiceManagement

// MARK: - Core Audio helpers

struct AudioDevice {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
}

private func address(_ selector: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

private func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
    return v.takeRetainedValue() as String
}

private func hasInputStreams(_ id: AudioDeviceID) -> Bool {
    var addr = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
}

func inputDevices() -> [AudioDevice] {
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

    return ids.compactMap { id in
        guard hasInputStreams(id),
              let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
              let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
        var transport: UInt32 = 0
        var tAddr = address(kAudioDevicePropertyTransportType)
        var tSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &tAddr, 0, nil, &tSize, &transport)
        return AudioDevice(id: id, uid: uid, name: name, transport: transport)
    }
}

func defaultInputID() -> AudioDeviceID {
    var addr = address(kAudioHardwarePropertyDefaultInputDevice)
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

func setDefaultInput(_ id: AudioDeviceID) {
    var addr = address(kAudioHardwarePropertyDefaultInputDevice)
    var dev = id
    AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                               UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let defaults = UserDefaults.standard

    private var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled"); updateIcon(); enforce() }
    }
    /// UID of the device to force; nil means "the built-in microphone".
    private var preferredUID: String? {
        get { defaults.string(forKey: "preferredUID") }
        set { defaults.set(newValue, forKey: "preferredUID"); enforce() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var addr = address(selector)
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main) { [weak self] _, _ in
                // Give a newly connected headset a moment to finish registering.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.enforce() }
            }
        }
        enforce()
    }

    private func targetDevice(in devices: [AudioDevice]) -> AudioDevice? {
        if let uid = preferredUID, let d = devices.first(where: { $0.uid == uid }) { return d }
        return devices.first(where: { $0.isBuiltIn })
    }

    private func enforce() {
        guard enabled else { return }
        let devices = inputDevices()
        guard let current = devices.first(where: { $0.id == defaultInputID() }), current.isBluetooth,
              let target = targetDevice(in: devices), target.id != current.id else { return }
        setDefaultInput(target.id)
    }

    private func updateIcon() {
        let name = enabled ? "mic.slash.circle" : "mic.circle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MicFixer")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !enabled
    }

    // Rebuild the menu each time it opens so the device list is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(title: "Keep Bluetooth mics off", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Use this mic instead:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let devices = inputDevices()
        let target = targetDevice(in: devices)
        let current = defaultInputID()
        for d in devices where !d.isBluetooth {
            let item = NSMenuItem(title: d.name + (d.id == current ? "  (active)" : ""),
                                  action: #selector(choose(_:)), keyEquivalent: "")
            item.representedObject = d.uid
            item.state = d.id == target?.id ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit MicFixer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
    }

    @objc private func toggleEnabled() { enabled.toggle() }

    @objc private func choose(_ sender: NSMenuItem) { preferredUID = sender.representedObject as? String }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login setting"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
