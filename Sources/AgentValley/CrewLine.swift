import Foundation

/// The text Claude Code's terminal shows under the prompt: the lead's face, model and plan, then
/// context and plan-limit meters drawn like the app's LimitMeter. Pure: it reads a dictionary
/// and returns a string.
enum CrewLine {
    /// Colours follow the terminal's own: plain text is the default foreground and the quiet
    /// parts are faint, so a light terminal reads as well as a dark one.
    enum Style {
        static let bold = "\u{1B}[1m"
        static let faint = "\u{1B}[2m"
        /// `LimitMeter.color`.
        static let yellow = "\u{1B}[38;2;250;209;64m"
        /// `MascotFlag.red`, kept for the rows that wait on the person.
        static let needsYou = "\u{1B}[38;2;255;69;59m"
        static let reset = "\u{1B}[0m"
    }

    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
        0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
        0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF,
        0x20000...0x3FFFD,
    ]

    /// The cells a text takes in a terminal. Colour codes take none; a character takes one or,
    /// for the wide ones, two. A Thai vowel or tone mark above or below a letter takes none of its own.
    static func width(_ text: String) -> Int {
        var plain = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            defer { i += 1 }
            // Only a real colour code, ESC "[" digits and ";" then "m", takes no room; any other
            // ESC is left alone so the text after it is still measured.
            if scalars[i] == "\u{1B}", i + 1 < scalars.count, scalars[i + 1] == "[" {
                var end = i + 2
                while end < scalars.count, scalars[end] == ";" || ("0"..."9").contains(scalars[end]) { end += 1 }
                if end < scalars.count, scalars[end] == "m" { i = end; continue }
            }
            plain.append(scalars[i])
        }
        // Per scalar, as a terminal does: marks and format characters join the cell before them,
        // but Thai sara am (U+0E33) is a spacing character and takes a cell of its own. An emoji
        // drawn as a picture takes two, as does a one-cell character that U+FE0F turns into one.
        var total = 0, previous = 0
        for scalar in plain {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .format:
                if scalar.value == 0xFE0F, previous == 1 { total += 1; previous = 2 }
            default:
                previous = scalar.properties.isEmojiPresentation || wideRanges.contains { $0.contains(scalar.value) } ? 2 : 1
                total += previous
            }
        }
        return total
    }

    /// The text cut to at most `cells` cells, ending in "…" when something was cut. Plain text only.
    static func cut(_ text: String, to cells: Int) -> String {
        guard cells > 0 else { return "" }
        guard width(text) > cells else { return text }
        var kept = "", used = 0
        for character in text {
            let w = width(String(character))
            if used + w > cells - 1 { break }
            kept.append(character)
            used += w
        }
        return kept + "…"
    }

    /// Text from Claude Code's JSON without control characters: a newline would split a row, an
    /// escape (or the 8-bit CSI, U+009B) would start a code of its own in the terminal, and a bidi
    /// mark would reorder the row on screen. A run of breaks becomes one space, so words stay apart;
    /// bidi marks, which are invisible, go.
    private static let breaks: [ClosedRange<UInt32>] = [0x00...0x1F, 0x7F...0x9F, 0x2028...0x2029]
    private static let bidi: [ClosedRange<UInt32>] = [
        0x061C...0x061C, 0x200E...0x200F, 0x202A...0x202E, 0x2066...0x2069,
    ]

    private static func clean(_ value: Any?) -> String {
        var text = String.UnicodeScalarView(), gap = false
        for scalar in (value as? String ?? "").unicodeScalars {
            if bidi.contains(where: { $0.contains(scalar.value) }) { continue }
            if breaks.contains(where: { $0.contains(scalar.value) }) { gap = true; continue }
            if gap, !text.isEmpty { text.append(" ") }
            gap = false
            text.append(scalar)
        }
        return String(text).trimmingCharacters(in: .whitespaces)
    }

    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    /// Cells of a bar that are full: none at 0% or less, at least one above it, all at 100%.
    static func bar(_ percent: Double, cells: Int) -> (full: Int, empty: Int) {
        let full = percent <= 0 ? 0 : min(cells, max(1, Int((percent / 100 * Double(cells)).rounded())))
        return (full, cells - full)
    }

    /// "Max 20x" from what Claude Code keeps in `~/.claude.json`; nil when it names no plan.
    static func plan(fromClaudeJSON json: [String: Any]?) -> String? {
        guard let account = json?["oauthAccount"] as? [String: Any],
              let type = account["organizationType"] as? String else { return nil }
        let name = type.replacingOccurrences(of: "claude_", with: "")
        guard let first = name.first else { return nil }
        let kind = first.uppercased() + name.dropFirst()
        let tier = account["organizationRateLimitTier"] as? String ?? ""
        let multiplier = tier.split(separator: "_").first { part in
            part.hasSuffix("x") && !part.dropLast().isEmpty && part.dropLast().allSatisfy(\.isNumber)
        }
        return multiplier.map { "\(kind) \($0)" } ?? kind
    }

    /// The top line and, when there is anything to measure, the meters below it.
    static func status(_ input: [String: Any], columns: Int, plan: String?, look: LeadLook, now: Date) -> String {
        let model = (input["model"] as? [String: Any])?["display_name"] as? String ?? ""
        var top = CrewFont.character(.lead(look), .working)
        let plan = plan.flatMap { $0.isEmpty ? nil : $0 }
        if !model.isEmpty {
            top += "  " + Style.bold + model + Style.reset
            if let plan { top += Style.faint + " · " + plan + Style.reset }
        } else if let plan {
            top += "  " + Style.faint + plan + Style.reset
        }

        let room = columns - 9
        let layouts: [(bar: Int, tokens: Bool, gap: String)] = [
            (10, true, "  │  "), (8, true, " │ "), (6, true, " │ "), (6, false, " │ "), (4, false, " │ "),
        ]
        var bottom = ""
        for layout in layouts {
            bottom = meters(input, bar: layout.bar, tokens: layout.tokens, gap: layout.gap, now: now)
            if width(bottom) <= room { break }
        }
        return bottom.isEmpty ? top : top + "\n" + bottom
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = (value as? NSNumber)?.doubleValue, value.isFinite, abs(value) < 1e12 else { return nil }
        return value
    }

    private static func meters(_ input: [String: Any], bar cells: Int, tokens: Bool, gap: String, now: Date) -> String {
        var parts: [String] = []
        let context = input["context_window"] as? [String: Any]
        if let used = number(context?["used_percentage"]) {
            let size = number(context?["context_window_size"]) ?? 0
            let tail = tokens && size > 0 ? "\(short(used / 100 * size))/\(short(size))" : ""
            parts.append(meter("ctx", PlanLimit(usedPercent: used, resetsAt: nil), cells: cells, tail: tail, now: now))
        }
        let limits = input["rate_limits"] as? [String: Any]
        for (key, name) in [("five_hour", "5h"), ("seven_day", "7d")] {
            guard let window = limits?[key] as? [String: Any], let used = number(window["used_percentage"]) else { continue }
            let resets = number(window["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            let limit = PlanLimit(usedPercent: used, resetsAt: resets)
            let tail = limit.resetLabel(now: now).map { "↻ " + $0 } ?? ""
            parts.append(meter(name, limit, cells: cells, tail: tail, now: now))
        }
        return parts.joined(separator: Style.faint + gap + Style.reset)
    }

    private static func meter(_ name: String, _ limit: PlanLimit, cells: Int, tail: String, now: Date) -> String {
        let (full, empty) = bar(limit.usedPercent, cells: cells)
        var number = limit.percentLabel
        if limit.level == .critical { number = "[\(number)]" }
        number = (limit.level == .normal ? Style.bold : Style.bold + Style.yellow) + number + Style.reset
        var text = Style.faint + name + Style.reset + " " + String(repeating: "━", count: full)
            + Style.faint + String(repeating: "━", count: empty) + Style.reset + " " + number
        if !tail.isEmpty { text += " " + Style.faint + tail + Style.reset }
        return text
    }

    /// Tokens as the app writes them: "220k", and "1.0m" from a million up.
    private static func short(_ n: Double) -> String {
        n >= 1_000_000 ? String(format: "%.1fm", n / 1_000_000) : "\(Int((n / 1000).rounded()))k"
    }

    /// What Claude Code calls a sub-agent that has finished.
    private static let doneStatuses: Set<String> = ["completed", "failed", "killed", "idle"]

    /// One JSON line per sub-agent, `{"id": ..., "content": ...}`, drawn like the notch panel's row:
    /// face, title, time and model; then folder and branch; then the current step.
    static func rows(_ input: [String: Any], now: Date, branch: (String) -> String) -> [String] {
        let tasks = input["tasks"] as? [[String: Any]] ?? []
        let columns = number(input["columns"]).map { Int($0) } ?? 80
        let room = columns - 6
        // Only live agents count, as in the app's panel.
        let oneLine = Format.oneLineRows(liveAgents: tasks.filter { !doneStatuses.contains($0["status"] as? String ?? "") }.count)
        var branches: [String: String] = [:]
        return tasks.compactMap { task in
            guard let id = task["id"] as? String else { return nil }
            let agentType = clean(task["agentType"])
            let description = clean(task["description"])
            let title = [description, agentType, clean(task["agent"])].first { !$0.isEmpty } ?? ""
            let model = Format.model(clean(task["model"]))

            let pose: CrewPose, when: String, whenStyle: String
            let status = task["status"] as? String ?? ""
            let done = doneStatuses.contains(status)
            if status == "waiting" {
                (pose, when, whenStyle) = (.needsYou, "needs you", Style.needsYou)
            } else if done {
                (pose, when, whenStyle) = (.done, "done", Style.faint)
            } else {
                let start = (task["startTime"] as? NSNumber)?.doubleValue ?? now.timeIntervalSince1970 * 1000
                (pose, when, whenStyle) = (.working, Format.elapsed(min(1e9, max(0, now.timeIntervalSince1970 - start / 1000))), "")
            }

            // The face takes two cells, then two spaces; the title gets what is left.
            let modelPart = model.isEmpty ? 0 : 2 + width(model)
            let titleRoom = room - 4 - 2 - width(when) - modelPart
            var top = CrewFont.character(MascotKind(type: agentType), pose) + "  "
                + Style.bold + cut(title, to: titleRoom) + Style.reset
                + "  " + whenStyle + when + Style.reset
            if !model.isEmpty { top += "  " + Style.faint + model + Style.reset }
            // With almost no room even the face and the time overflow, so the whole line is cut.
            if width(top) > room {
                top = cut(plain(top), to: room)
            }
            var lines = [top]

            if !oneLine {
                let cwd = clean(task["cwd"])
                if !cwd.isEmpty {
                    let folder = (cwd as NSString).lastPathComponent
                    let name = branches[cwd] ?? clean(branch(cwd))
                    branches[cwd] = name
                    let place = "▭ " + folder + (name.isEmpty ? "" : "  ⑂ " + name)
                    lines.append("    " + Style.faint + cut(place, to: room - 4) + Style.reset)
                }
                let step = clean(task["label"])
                if !step.isEmpty, step != description {
                    lines.append("    " + cut("> " + step, to: room - 4) + Style.reset)
                }
            }
            // Rows of a finished agent are faint all through.
            if done { lines = lines.map { Style.faint + $0 } }
            let json = try? JSONSerialization.data(withJSONObject: ["id": id, "content": lines.joined(separator: "\n")])
            return json.map { String(decoding: $0, as: UTF8.self) }
        }
    }

    /// The branch a folder is on, read from `.git/HEAD` the way git keeps it, so no process runs.
    /// Empty outside a repository and when HEAD names a commit instead of a branch.
    static func branch(of folder: String) -> String {
        var directory = folder
        while true {
            let dot = directory + "/.git"
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dot, isDirectory: &isDirectory) {
                var git = dot
                if !isDirectory.boolValue {
                    // A worktree's .git is a file naming the real git folder, maybe relative to this one.
                    let line = AgentStore.head(ofPlainFile: dot).split(separator: "\n").first.map(String.init) ?? ""
                    guard line.hasPrefix("gitdir:") else { return "" }
                    let path = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    git = path.hasPrefix("/") ? path : directory + "/" + path
                }
                let head = AgentStore.head(ofPlainFile: git + "/HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
                return head.hasPrefix("ref: refs/heads/") ? String(head.dropFirst(16)) : ""
            }
            let parent = (directory as NSString).deletingLastPathComponent
            if parent == directory || parent.isEmpty { return "" }
            directory = parent
        }
    }
}
