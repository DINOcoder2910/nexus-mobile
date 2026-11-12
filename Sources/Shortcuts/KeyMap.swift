import SwiftUI
import UIKit
import NexusCore

/// Between a binding as the files write it ("Cmd+Shift+Z") and what iPadOS takes: SwiftUI's KeyboardShortcut, UIKit's UIKeyCommand,
/// and back from a pressed key (UIKey) when Settings › Shortcuts records a new one.
enum KeyMap {
    /// One step with a key (nil for two steps or a modifiers-only binding, which the iPad doesn't run).
    static func single(_ binding: String) -> (mods: [String], key: String)? {
        guard !binding.trimmingCharacters(in: .whitespaces).contains(" ") else { return nil }
        let p = ShortcutKeys.parts(binding, device: ShortcutRegistry.device)
        guard let key = p.key else { return nil }
        return (p.mods, key)
    }

    // MARK: SwiftUI

    static func swiftUI(_ binding: String) -> KeyboardShortcut? {
        guard let one = single(binding), let k = equivalent(one.key) else { return nil }
        var m: EventModifiers = []
        for mod in one.mods {
            switch mod {
            case "Cmd": m.insert(.command)
            case "Ctrl": m.insert(.control)
            case "Alt": m.insert(.option)
            case "Shift": m.insert(.shift)
            default: return nil
            }
        }
        return KeyboardShortcut(k, modifiers: m)
    }

    static func equivalent(_ key: String) -> KeyEquivalent? {
        switch key {
        case "Enter": return .return
        case "Esc": return .escape
        case "Tab": return .tab
        case "Space": return .space
        case "Backspace": return .delete
        case "Delete": return .deleteForward
        case "Up": return .upArrow
        case "Down": return .downArrow
        case "Left": return .leftArrow
        case "Right": return .rightArrow
        case "PageUp": return .pageUp
        case "PageDown": return .pageDown
        case "Home": return .home
        case "End": return .end
        default:
            guard key.count == 1, let c = key.lowercased().first else { return nil }
            return KeyEquivalent(c)
        }
    }

    // MARK: UIKit

    static func keyCommand(_ binding: String, title: String, id: String, action: Selector) -> UIKeyCommand? {
        guard let one = single(binding), let typed = input(one.key) else { return nil }
        var flags: UIKeyModifierFlags = []
        for mod in one.mods {
            switch mod {
            case "Cmd": flags.insert(.command)
            case "Ctrl": flags.insert(.control)
            case "Alt": flags.insert(.alternate)
            case "Shift": flags.insert(.shift)
            default: return nil
            }
        }
        let c = UIKeyCommand(title: title, image: nil, action: action, input: typed, modifierFlags: flags, propertyList: id)
        c.wantsPriorityOverSystemBehavior = true
        return c
    }

    static func input(_ key: String) -> String? {
        switch key {
        case "Enter": return "\r"
        case "Esc": return UIKeyCommand.inputEscape
        case "Tab": return "\t"
        case "Space": return " "
        case "Backspace": return "\u{8}"
        case "Delete": return UIKeyCommand.inputDelete
        case "Up": return UIKeyCommand.inputUpArrow
        case "Down": return UIKeyCommand.inputDownArrow
        case "Left": return UIKeyCommand.inputLeftArrow
        case "Right": return UIKeyCommand.inputRightArrow
        case "PageUp": return UIKeyCommand.inputPageUp
        case "PageDown": return UIKeyCommand.inputPageDown
        case "Home": return UIKeyCommand.inputHome
        case "End": return UIKeyCommand.inputEnd
        case "F1": return UIKeyCommand.f1
        case "F2": return UIKeyCommand.f2
        case "F3": return UIKeyCommand.f3
        case "F4": return UIKeyCommand.f4
        case "F5": return UIKeyCommand.f5
        case "F6": return UIKeyCommand.f6
        case "F7": return UIKeyCommand.f7
        case "F8": return UIKeyCommand.f8
        case "F9": return UIKeyCommand.f9
        case "F10": return UIKeyCommand.f10
        case "F11": return UIKeyCommand.f11
        case "F12": return UIKeyCommand.f12
        default: return key.count == 1 ? key.lowercased() : nil
        }
    }

    // MARK: recording a key

    /// The key's name from its keyboard usage code (so Shift or Option never change what it is called), or nil for a modifier.
    static func name(_ code: Int) -> String? {
        switch code {
        case 4...29: return String(UnicodeScalar(UInt8(65 + code - 4)))
        case 30...38: return String(code - 29)
        case 39: return "0"
        case 40, 88: return "Enter"
        case 41: return "Esc"
        case 42: return "Backspace"
        case 43: return "Tab"
        case 44: return "Space"
        case 45: return "-"
        case 46: return "="
        case 47: return "["
        case 48: return "]"
        case 49: return "\\"
        case 51: return ";"
        case 52: return "'"
        case 53: return "`"
        case 54: return ","
        case 55: return "."
        case 56: return "/"
        case 58...69: return "F\(code - 57)"
        case 70: return "PrintScreen"
        case 74: return "Home"
        case 75: return "PageUp"
        case 76: return "Delete"
        case 77: return "End"
        case 78: return "PageDown"
        case 79: return "Right"
        case 80: return "Left"
        case 81: return "Down"
        case 82: return "Up"
        default: return nil
        }
    }

    /// The modifiers held, named for the device being edited: for the laptop ⌘ counts as Ctrl (Win is picked by hand).
    static func modifiers(_ flags: UIKeyModifierFlags, device: String) -> Set<String> {
        var out = Set<String>()
        if flags.contains(.command) { out.insert(device == "ipad" ? "Cmd" : "Ctrl") }
        if flags.contains(.control) { out.insert("Ctrl") }
        if flags.contains(.alternate) { out.insert("Alt") }
        if flags.contains(.shift) { out.insert("Shift") }
        return out
    }

    /// A pressed key as a binding for `device`, or nil while only modifiers are down.
    static func binding(_ key: UIKey, device: String) -> String? {
        guard let keyName = name(key.keyCode.rawValue) else { return nil }
        return ShortcutKeys.make(mods: modifiers(key.modifierFlags, device: device), key: keyName, device: device)
    }

    /// The keys the picker offers (when there is no hardware keyboard, or for a key it can't record).
    static func pickable(device: String) -> [String] {
        let letters = (65...90).map { String(UnicodeScalar(UInt8($0))) }
        let digits = (0...9).map(String.init)
        var named = ["Enter", "Esc", "Tab", "Space", "Backspace", "Delete", "Up", "Down", "Left", "Right", "PageUp", "PageDown", "Home", "End"]
        named += (1...12).map { "F\($0)" }
        if device != "ipad" { named.append("PrintScreen") }
        return letters + digits + ShortcutKeys.symbols + named
    }
}
