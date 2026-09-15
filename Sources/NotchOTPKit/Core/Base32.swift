import Foundation

/// RFC 4648 base32, the alphabet `otpauth://` secrets are written in.
///
/// Only decoding is implemented: secrets travel from the user to the YubiKey and are
/// never written back out, so there is nothing to encode.
public enum Base32 {

    /// Decodes `text` as RFC 4648 base32 (`A`–`Z` then `2`–`7`).
    ///
    /// Case-insensitive, and separators are ignored, so a secret copied out of Yubico
    /// Authenticator as `abcd efgh ijkl` or `ABCD-EFGH-IJKL` decodes as typed. Padding
    /// is accepted but must close the final 8-character group (`MZXW6===`): a
    /// half-padded `MZXW6=` is a cut-off secret rather than a shorter one.
    ///
    /// - Returns: the decoded bytes, or `nil` when a character is outside the alphabet,
    ///   when the padding does not complete the last group, or when the bit stream is
    ///   truncated — too few bits for the last byte, or leftover bits that are not zero.
    public static func decode(_ text: String) -> Data? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count * 5 / 8 + 1)

        var accumulator: UInt32 = 0
        var bitCount = 0
        var dataCount = 0
        var paddingCount = 0
        var sawPadding = false

        for character in text {
            if character.isWhitespace || character == "-" { continue }

            if character == "=" {
                sawPadding = true
                paddingCount += 1
                continue
            }

            // Payload after padding would mean the '=' were not trailing.
            guard !sawPadding, let value = value(of: character) else { return nil }

            dataCount += 1
            accumulator = (accumulator << 5) | UInt32(value)
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                bytes.append(UInt8(truncatingIfNeeded: accumulator >> UInt32(bitCount)))
                accumulator &= bitCount == 0 ? 0 : (1 << UInt32(bitCount)) - 1
            }
        }

        if paddingCount > 0 {
            // Padding only ever completes a group of eight characters.
            guard (dataCount + paddingCount) % 8 == 0,
                  paddingCount == (8 - dataCount % 8) % 8
            else { return nil }
        }

        // A well-formed length leaves 0 to 4 bits over. Five or more is a half-written
        // character; non-zero leftovers mean the encoder padded with garbage.
        guard bitCount < 5, accumulator == 0 else { return nil }

        return Data(bytes)
    }

    /// Alphabet position of one base32 character, `nil` for anything else.
    private static func value(of character: Character) -> UInt8? {
        guard let ascii = character.asciiValue else { return nil }
        switch ascii {
        case 0x41...0x5A: return ascii - 0x41          // A-Z
        case 0x61...0x7A: return ascii - 0x61          // a-z
        case 0x32...0x37: return ascii - 0x32 + 26     // 2-7
        default: return nil
        }
    }
}
