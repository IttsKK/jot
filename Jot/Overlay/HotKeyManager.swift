import Carbon
import Foundation

private let jotHotKeySignature = OSType(0x4A4F5448) // "JOTH"

struct HotKeyShortcut {
    var keyCode: UInt32
    var modifiers: UInt32
}

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var callbacks: [UInt32: () -> Void] = [:]

    private init() {}

    deinit {
        unregisterAll()
    }

    @discardableResult
    func register(id: UInt32, shortcut: HotKeyShortcut, callback: @escaping () -> Void) -> Bool {
        unregister(id: id)
        callbacks[id] = callback
        installEventHandlerIfNeeded()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: jotHotKeySignature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr, let hotKeyRef {
            hotKeyRefs[id] = hotKeyRef
            return true
        } else {
            callbacks.removeValue(forKey: id)
            return false
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return noErr }
            if hotKeyID.signature == jotHotKeySignature {
                manager.callbacks[hotKeyID.id]?()
            }
            return noErr
        }, 1, &eventSpec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandler)
    }

    func unregister(id: UInt32) {
        if let hotKeyRef = hotKeyRefs[id] {
            UnregisterEventHotKey(hotKeyRef)
            hotKeyRefs.removeValue(forKey: id)
        }
        callbacks.removeValue(forKey: id)
        uninstallEventHandlerIfUnused()
    }

    func unregisterAll() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        callbacks.removeAll()
        uninstallEventHandlerIfUnused()
    }

    private func uninstallEventHandlerIfUnused() {
        guard callbacks.isEmpty else { return }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
