import Carbon

/// A system-wide shortcut through Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission. Released when the object goes away.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// nil when another app already holds the shortcut.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action()
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x4350_5246), id: 1)  // "CPRF"
        guard
            RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr
        else {
            RemoveEventHandler(handler)
            handler = nil
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// ⌃⌥⇥, the shortcut that rotates profiles.
    static func cycleProfiles(_ action: @escaping () -> Void) -> HotKey? {
        HotKey(keyCode: kVK_Tab, modifiers: controlKey | optionKey, action: action)
    }
}
