import Foundation

/// Local shortcut description. Registering it does not send input to other apps.
public struct HotKeySpec: Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public static let signature: UInt32 = 0x4342_4152
    public static let defaultKeyCode: UInt32 = 8
    public static let command: UInt32 = 256
    public static let shift: UInt32 = 512
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096
    public static let `default` = HotKeySpec(
        keyCode: defaultKeyCode,
        carbonModifiers: command | option
    )

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public var display: String {
        var prefix = ""
        if carbonModifiers & HotKeySpec.control != 0 { prefix += "⌃" }
        if carbonModifiers & HotKeySpec.option != 0 { prefix += "⌥" }
        if carbonModifiers & HotKeySpec.shift != 0 { prefix += "⇧" }
        if carbonModifiers & HotKeySpec.command != 0 { prefix += "⌘" }
        return prefix + HotKeySpec.glyph(for: keyCode)
    }

    public static func glyph(for keyCode: UInt32) -> String {
        let letters: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M"
        ]
        if let letter = letters[keyCode] { return letter }
        return "#\(keyCode)"
    }
}
