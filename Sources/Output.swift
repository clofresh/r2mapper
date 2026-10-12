import AppKit
import CoreGraphics

/// Sends keystrokes and runs shell commands.
enum Output {
    static let keyCodes: [String: CGKeyCode] = {
        var map: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
            "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "n": 45, "m": 46, ".": 47, "`": 50,
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "esc": 53,
            "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "left": 123, "right": 124, "down": 125, "up": 126,
        ]
        let fKeys: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in fKeys.enumerated() { map["f\(i + 1)"] = code }
        return map
    }()

    static let modifierFlags: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "shift": .maskShift,
        "option": .maskAlternate, "alt": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl,
        "fn": .maskSecondaryFn,
    ]

    /// Returns an error message if the action couldn't be performed.
    @discardableResult
    static func perform(_ action: Action) -> String? {
        if let key = action.key {
            guard let code = keyCodes[key.lowercased()] else { return "Unknown key \"\(key)\"" }
            var flags: CGEventFlags = []
            for name in action.modifiers ?? [] {
                guard let flag = modifierFlags[name.lowercased()] else { return "Unknown modifier \"\(name)\"" }
                flags.insert(flag)
            }
            if ["left", "right", "up", "down"].contains(key.lowercased()) {
                flags.insert([.maskNumericPad, .maskSecondaryFn])
            }
            let source = CGEventSource(stateID: .hidSystemState)
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
                event?.flags = flags
                event?.post(tap: .cghidEventTap)
            }
        }
        if let shell = action.shell {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", shell]
            do { try process.run() } catch { return "Shell command failed: \(error.localizedDescription)" }
        }
        return nil
    }
}
