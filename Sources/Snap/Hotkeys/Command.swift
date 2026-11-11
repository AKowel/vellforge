import Carbon.HIToolbox
import SnapCore

/// Everything Snap can be asked to do, in one list — so shortcuts, the menu
/// and preferences all iterate the same source of truth.
enum Command: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case maximize, center
    case nextDisplay, previousDisplay

    var snapAction: SnapAction? {
        switch self {
        case .nextDisplay, .previousDisplay: return nil
        default: return SnapAction(rawValue: rawValue)
        }
    }

    var displayAction: DisplayAction? {
        switch self {
        case .nextDisplay:     return .nextDisplay
        case .previousDisplay: return .previousDisplay
        default:               return nil
        }
    }

    var title: String {
        snapAction?.title ?? displayAction?.title ?? rawValue
    }

    /// Grouping for the preferences list and the menu separators.
    var group: String {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf:         return "Halves"
        case .topLeft, .topRight, .bottomLeft, .bottomRight:       return "Quarters"
        case .leftThird, .centerThird, .rightThird,
             .leftTwoThirds, .rightTwoThirds:                      return "Thirds"
        case .maximize, .center:                                   return "Whole screen"
        case .nextDisplay, .previousDisplay:                       return "Displays"
        }
    }

    /// Defaults follow the conventions people already have muscle memory for
    /// from Rectangle and Magnet — ⌃⌥ plus a direction.
    var defaultBinding: KeyBinding? {
        let ctrlOpt = UInt32(controlKey) | UInt32(optionKey)
        let ctrlOptCmd = ctrlOpt | UInt32(cmdKey)
        switch self {
        case .leftHalf:        return KeyBinding(keyCode: kVK_LeftArrow,  modifiers: ctrlOpt)
        case .rightHalf:       return KeyBinding(keyCode: kVK_RightArrow, modifiers: ctrlOpt)
        case .topHalf:         return KeyBinding(keyCode: kVK_UpArrow,    modifiers: ctrlOpt)
        case .bottomHalf:      return KeyBinding(keyCode: kVK_DownArrow,  modifiers: ctrlOpt)
        case .topLeft:         return KeyBinding(keyCode: kVK_ANSI_U,     modifiers: ctrlOpt)
        case .topRight:        return KeyBinding(keyCode: kVK_ANSI_I,     modifiers: ctrlOpt)
        case .bottomLeft:      return KeyBinding(keyCode: kVK_ANSI_J,     modifiers: ctrlOpt)
        case .bottomRight:     return KeyBinding(keyCode: kVK_ANSI_K,     modifiers: ctrlOpt)
        case .leftThird:       return KeyBinding(keyCode: kVK_ANSI_D,     modifiers: ctrlOpt)
        case .centerThird:     return KeyBinding(keyCode: kVK_ANSI_F,     modifiers: ctrlOpt)
        case .rightThird:      return KeyBinding(keyCode: kVK_ANSI_G,     modifiers: ctrlOpt)
        case .leftTwoThirds:   return KeyBinding(keyCode: kVK_ANSI_E,     modifiers: ctrlOpt)
        case .rightTwoThirds:  return KeyBinding(keyCode: kVK_ANSI_T,     modifiers: ctrlOpt)
        case .maximize:        return KeyBinding(keyCode: kVK_Return,     modifiers: ctrlOpt)
        case .center:          return KeyBinding(keyCode: kVK_ANSI_C,     modifiers: ctrlOpt)
        case .nextDisplay:     return KeyBinding(keyCode: kVK_RightArrow, modifiers: ctrlOptCmd)
        case .previousDisplay: return KeyBinding(keyCode: kVK_LeftArrow,  modifiers: ctrlOptCmd)
        }
    }

    static let groups = ["Halves", "Quarters", "Thirds", "Whole screen", "Displays"]
}
