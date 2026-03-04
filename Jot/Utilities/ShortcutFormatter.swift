import AppKit
import Carbon
import Foundation

struct ShortcutKeyOption: Identifiable, Hashable {
    var label: String
    var keyCode: UInt32

    var id: UInt32 { keyCode }
}

enum ShortcutFormatter {
    static let keyOptions: [ShortcutKeyOption] = [
        .init(label: "Space", keyCode: 49),
        .init(label: "A", keyCode: 0),
        .init(label: "B", keyCode: 11),
        .init(label: "C", keyCode: 8),
        .init(label: "D", keyCode: 2),
        .init(label: "E", keyCode: 14),
        .init(label: "F", keyCode: 3),
        .init(label: "G", keyCode: 5),
        .init(label: "H", keyCode: 4),
        .init(label: "I", keyCode: 34),
        .init(label: "J", keyCode: 38),
        .init(label: "K", keyCode: 40),
        .init(label: "L", keyCode: 37),
        .init(label: "M", keyCode: 46),
        .init(label: "N", keyCode: 45),
        .init(label: "O", keyCode: 31),
        .init(label: "P", keyCode: 35),
        .init(label: "Q", keyCode: 12),
        .init(label: "R", keyCode: 15),
        .init(label: "S", keyCode: 1),
        .init(label: "T", keyCode: 17),
        .init(label: "U", keyCode: 32),
        .init(label: "V", keyCode: 9),
        .init(label: "W", keyCode: 13),
        .init(label: "X", keyCode: 7),
        .init(label: "Y", keyCode: 16),
        .init(label: "Z", keyCode: 6)
    ]

    static func keyLabel(for keyCode: UInt32) -> String {
        keyOptions.first(where: { $0.keyCode == keyCode })?.label ?? "Key \(keyCode)"
    }

    static func keyEquivalent(for keyCode: UInt32) -> String {
        if keyCode == 49 {
            return " "
        }
        return keyLabel(for: keyCode).lowercased()
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

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("Control")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("Option")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("Command")
        }
        parts.append(keyLabel(for: keyCode))
        return parts.joined(separator: "+")
    }
}
