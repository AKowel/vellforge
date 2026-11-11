import AppKit
import Carbon.HIToolbox

/// Registers system-wide shortcuts via Carbon's `RegisterEventHotKey`.
///
/// Carbon rather than a `CGEvent` tap on purpose: hotkey registration needs no
/// extra permission beyond what Snap already has, cannot be disabled by the
/// system under load, and does not see keystrokes it has not asked for.
@MainActor
final class HotKeyManager {

    static let shared = HotKeyManager()
    private init() {}

    /// Four-char code 'VSNP', identifying our hotkeys to Carbon.
    private static let signature: OSType = 0x56534E50

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    /// Returns false when the combination is already claimed by the system or
    /// another app — a real and common outcome, so callers must handle it.
    @discardableResult
    func register(_ binding: KeyBinding, action: @escaping @MainActor () -> Void) -> Bool {
        guard binding.hasModifiers else { return false }
        installHandlerIfNeeded()

        let id = nextID
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(binding.keyCode,
                                         binding.modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else { return false }

        nextID += 1
        refs[id] = ref
        handlers[id] = action
        return true
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }
}

/// Carbon delivers hotkey events on the main thread, which is what makes
/// `assumeIsolated` sound here.
private let hotKeyCallback: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return status }

    MainActor.assumeIsolated {
        HotKeyManager.shared.fire(id: hotKeyID.id)
    }
    return noErr
}
