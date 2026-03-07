import AppKit
import Carbon
import Foundation

enum ShortcutFormatter {
    private static let keyLabels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Esc", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
        115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
        119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "Left Arrow",
        124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow"
    ]

    private static let menuKeyEquivalents: [UInt32: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "\r",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "n", 46: "m", 47: ".", 48: "\t", 49: " ", 50: "`",
        51: String(UnicodeScalar(NSBackspaceCharacter)!),
        53: "\u{1b}",
        96: String(UnicodeScalar(NSF5FunctionKey)!),
        97: String(UnicodeScalar(NSF6FunctionKey)!),
        98: String(UnicodeScalar(NSF7FunctionKey)!),
        99: String(UnicodeScalar(NSF3FunctionKey)!),
        100: String(UnicodeScalar(NSF8FunctionKey)!),
        101: String(UnicodeScalar(NSF9FunctionKey)!),
        103: String(UnicodeScalar(NSF11FunctionKey)!),
        109: String(UnicodeScalar(NSF10FunctionKey)!),
        111: String(UnicodeScalar(NSF12FunctionKey)!),
        115: String(UnicodeScalar(NSHomeFunctionKey)!),
        116: String(UnicodeScalar(NSPageUpFunctionKey)!),
        117: String(UnicodeScalar(NSDeleteFunctionKey)!),
        118: String(UnicodeScalar(NSF4FunctionKey)!),
        119: String(UnicodeScalar(NSEndFunctionKey)!),
        120: String(UnicodeScalar(NSF2FunctionKey)!),
        121: String(UnicodeScalar(NSPageDownFunctionKey)!),
        122: String(UnicodeScalar(NSF1FunctionKey)!),
        123: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
        124: String(UnicodeScalar(NSRightArrowFunctionKey)!),
        125: String(UnicodeScalar(NSDownArrowFunctionKey)!),
        126: String(UnicodeScalar(NSUpArrowFunctionKey)!)
    ]

    static func keyLabel(for keyCode: UInt32) -> String {
        keyLabels[keyCode] ?? "Key \(keyCode)"
    }

    static func keyEquivalent(for keyCode: UInt32) -> String {
        menuKeyEquivalents[keyCode] ?? ""
    }

    static func modifierMask(for carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 {
            mask.insert(.command)
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            mask.insert(.option)
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            mask.insert(.shift)
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            mask.insert(.control)
        }
        return mask
    }

    static func carbonModifiers(from eventModifiers: NSEvent.ModifierFlags) -> UInt32 {
        let flags = eventModifiers.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.control) {
            carbon |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            carbon |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            carbon |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            carbon |= UInt32(cmdKey)
        }
        return carbon
    }

    static func modifierDisplayString(modifiers: UInt32) -> String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 {
            value += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            value += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            value += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            value += "⌘"
        }
        return value
    }

    static func isModifierOnlyKey(_ keyCode: UInt32) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        guard keyCode != 0 else { return "Not Set" }
        let modifiersText = modifierDisplayString(modifiers: modifiers)
        return modifiersText + keyLabel(for: keyCode)
    }
}
