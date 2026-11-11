import AppKit
import Carbon.HIToolbox

/// A global shortcut, stored in Carbon's vocabulary because that is what
/// `RegisterEventHotKey` speaks.
struct KeyBinding: Codable, Equatable, Sendable {
    var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(keyCode: Int, modifiers: UInt32) {
        self.init(keyCode: UInt32(keyCode), modifiers: modifiers)
    }

    // MARK: Conversion to and from AppKit, for the recorder UI

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option)  { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift)   { mask |= UInt32(shiftKey) }
        return mask
    }

    /// A shortcut with no modifiers would swallow ordinary typing system-wide.
    var hasModifiers: Bool { modifiers != 0 }

    // MARK: Display

    var displayString: String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { out += "⌘" }
        out += Self.keyName(for: keyCode)
        return out
    }

    static func keyName(for keyCode: UInt32) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        if let letter = letterKeys[Int(keyCode)] { return letter }
        return "Key \(keyCode)"
    }

    private static let specialKeys: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑",   kVK_DownArrow: "↓",
        kVK_Return: "↩",    kVK_Space: "Space",
        kVK_Escape: "⎋",    kVK_Tab: "⇥",
        kVK_Delete: "⌫",
    ]

    private static let letterKeys: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_9: "9", kVK_ANSI_0: "0",
    ]
}

// MARK: - Bridging to NSMenuItem
//
// Showing the shortcut beside each menu row is the cheapest discovery mechanism
// there is — people learn the hotkeys by seeing them while clicking.

extension KeyBinding {
    var appKitModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        return flags
    }

    /// The string `NSMenuItem.keyEquivalent` expects. Arrow keys are expressed
    /// as function-key code points, not the arrow glyphs.
    var menuKeyEquivalent: String? {
        func fn(_ code: Int) -> String {
            String(utf16CodeUnits: [unichar(code)], count: 1)
        }
        switch Int(keyCode) {
        case kVK_LeftArrow:  return fn(NSLeftArrowFunctionKey)
        case kVK_RightArrow: return fn(NSRightArrowFunctionKey)
        case kVK_UpArrow:    return fn(NSUpArrowFunctionKey)
        case kVK_DownArrow:  return fn(NSDownArrowFunctionKey)
        case kVK_Return:     return "\r"
        case kVK_Space:      return " "
        default:             return Self.letterKeys[Int(keyCode)]?.lowercased()
        }
    }
}
