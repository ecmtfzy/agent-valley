import AppKit
import Carbon.HIToolbox

/// The one system-wide shortcut: Control, Option and Command with a letter. It uses the Carbon
/// hot-key API, which asks the person for no permission: the app is told of this one chord and
/// of no other key.
final class Hotkey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    /// The chord that is registered now.
    private var key = ShortcutKey.a

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        setEnabled(false, key: key)
    }

    /// Whether the chord is this app's afterwards. It is not when another app holds it already.
    @discardableResult
    func setEnabled(_ on: Bool, key: ShortcutKey) -> Bool {
        // Another chord than the one held: let that one go first.
        if on, hotKey != nil, key != self.key { setEnabled(false, key: self.key) }
        self.key = key
        guard on != (hotKey != nil) else { return on }
        guard on else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            if let handler { RemoveEventHandler(handler) }
            hotKey = nil
            handler = nil
            return false
        }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let listening = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        // With nothing listening the chord must not be taken: it would be held from every app and do nothing.
        guard listening == noErr, handler != nil else {
            handler = nil
            return false
        }
        // "AVKY": the app's own mark on the registration.
        let id = EventHotKeyID(signature: OSType(0x4156_4B59), id: 1)
        let registered = RegisterEventHotKey(key.keyCode, UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
        // Refused: nothing is left listening for a chord that will never come.
        if registered != noErr || hotKey == nil {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            if let handler { RemoveEventHandler(handler) }
            handler = nil
        }
        return hotKey != nil
    }
}
