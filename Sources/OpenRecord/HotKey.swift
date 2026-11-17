import Carbon.HIToolbox

/// A system-wide shortcut via Carbon's RegisterEventHotKey, which (unlike event taps) needs no
/// Accessibility permission.
@MainActor
final class HotKey {
    static let keyR = UInt32(kVK_ANSI_R)
    static let controlOption = UInt32(controlKey | optionKey)
    static let controlOptionShift = UInt32(controlKey | optionKey | shiftKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void
    private let registeredID: UInt32

    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action
        registeredID = id
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F50_5243), id: id)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var incomingID = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &incomingID)
                guard status == noErr else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                guard incomingID.id == hotKey.registeredID else { return noErr }
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        let registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard installed == noErr, registered == noErr else { return nil }
    }

    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
