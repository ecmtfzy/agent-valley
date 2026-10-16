import Foundation

/// JSON that some other program wrote: transcripts, session records, hook input, the Keychain
/// item and the usage reply. Every such text is parsed here and nowhere else.
enum SafeJSON {
    /// Past this many arrays and objects inside one another, nothing is parsed. Foundation's
    /// parser calls itself once per level, and off the main thread it overruns its stack at some
    /// 450 objects deep: a crash, where text that is not JSON only fails. Of the 470,000
    /// transcript lines on the owner's Mac, the deepest stood 15 deep.
    static let maxDepth = 128

    /// The object `data` holds, or nil when it is not one or nests too deep to parse.
    static func object(_ data: Data) -> [String: Any]? {
        guard nests(data, atMost: maxDepth) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Whether the brackets of `data`, outside its strings, never stand more than `limit` deep.
    /// Counted as written: text that is not JSON gets an answer too, and the parser turns it
    /// away afterwards. False for any text with a zero byte. UTF-8 JSON has none, and the
    /// parser also reads UTF-16 and UTF-32, where a quote's byte can be half of some other
    /// character and the count of what stands inside a string would be wrong.
    static func nests(_ data: Data, atMost limit: Int) -> Bool {
        data.withUnsafeBytes { bytes in
            var depth = 0, inString = false, escaped = false
            for byte in bytes {
                if byte == 0 { return false }
                if inString {
                    if escaped {
                        escaped = false
                    } else if byte == UInt8(ascii: "\\") {
                        escaped = true
                    } else if byte == UInt8(ascii: "\"") {
                        inString = false
                    }
                    continue
                }
                switch byte {
                case UInt8(ascii: "\""):
                    inString = true
                case UInt8(ascii: "["), UInt8(ascii: "{"):
                    depth += 1
                    if depth > limit { return false }
                case UInt8(ascii: "]"), UInt8(ascii: "}"):
                    depth -= 1
                default:
                    break
                }
            }
            return true
        }
    }
}
