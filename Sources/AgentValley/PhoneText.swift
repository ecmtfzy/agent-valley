import Foundation

/// Text sent from the phone, cleaned before it is typed into a terminal session.
enum PhoneText {
    /// The longest message the phone may send. SessionSender checks it; clean does not cut.
    static let maxCharacters = 8000

    /// Line breaks become "\n", tabs become spaces, other control characters are dropped.
    /// Returns nil when nothing but whitespace is left.
    static func clean(_ raw: String) -> String? {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        var kept = String.UnicodeScalarView()
        for scalar in lines.unicodeScalars {
            if scalar == "\t" {
                kept.append(" ")
            } else if scalar == "\n" || scalar.properties.generalCategory != .control {
                kept.append(scalar)
            }
        }
        let trimmed = String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Multi-line text goes in as a bracketed paste so the terminal does not run each line.
    /// Ghostty gets it raw: it tells no paste markers apart from typing.
    /// Terminal's `do script` presses Return after the text on its own; a backslash before it makes
    /// that Return a new line in Claude Code (and a line that goes on, in a shell), so only Enter sends.
    static func typed(_ text: String, for terminal: TabPlace.Terminal) -> String {
        let body = terminal != .ghostty && text.unicodeScalars.contains("\n") ? "\u{1B}[200~" + text + "\u{1B}[201~" : text
        guard terminal == .terminal else { return body }
        return body + (body.hasSuffix("\\") ? " \\" : "\\")
    }
}
