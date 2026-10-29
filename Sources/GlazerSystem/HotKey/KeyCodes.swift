import Carbon.HIToolbox
import GlazerCore

/// Virtual key codes for the keys a ``KeyboardShortcut`` can use.
///
/// Key codes are physical positions on an ANSI keyboard, so on other layouts a shortcut
/// stays on the same key.
public enum KeyCodes {
    private static let codes: [Character: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D,
        "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H,
        "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
        "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P,
        "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
        "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
        "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "←": kVK_LeftArrow, "→": kVK_RightArrow, "↑": kVK_UpArrow, "↓": kVK_DownArrow,
        " ": kVK_Space,
    ]

    private static let keys = Dictionary(uniqueKeysWithValues: codes.map { ($0.value, $0.key) })

    /// The key code for `key`, or `nil` if shortcuts can't use it.
    public static func code(for key: Character) -> UInt32? {
        codes[key].map(UInt32.init)
    }

    /// The key at `code`, or `nil` if shortcuts can't use it.
    public static func key(for code: UInt16) -> Character? {
        keys[Int(code)]
    }
}
