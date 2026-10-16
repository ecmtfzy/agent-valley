import Foundation

/// Which project a folder belongs to, told by its path alone: most folders sessions worked in
/// are gone by the time anyone asks (144 of 163 on the owner's Mac on 2026-10-15), so git
/// cannot be asked.
enum Projects {
    static let scratch = "Scratch"
    static let temporary = "Temporary folders"
    static let supersetSessions = "Superset sessions"
    static let unknown = "Unknown folder"

    /// A folder as Claude Code spells it in the names of its own folders: everything but
    /// letters and digits as "-".
    static func encoded(_ folder: String) -> String {
        String(folder.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
    }

    /// Encoded folders back to the folders, to name a session's scratch folder by.
    static func known(_ folders: [String]) -> [String: String] {
        Dictionary(folders.map { (encoded($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The project's name, by the first rule that fits.
    static func name(of folder: String, home: String, known: [String: String] = [:]) -> String {
        if folder.isEmpty { return unknown }
        // A session's scratch folder: /tmp/claude-<uid>/<its session's folder, encoded>/<session>/…
        for tmp in ["/tmp/claude-", "/private/tmp/claude-"] where folder.hasPrefix(tmp) {
            let parts = folder.dropFirst(tmp.count).split(separator: "/")
            guard parts.count >= 2, let real = known[String(parts[1])], !isTemporary(real) else { return scratch }
            return name(of: real, home: home)
        }
        if isTemporary(folder) { return temporary }
        var path = folder
        if let worktrees = path.range(of: "/.claude/worktrees/") { path = String(path[..<worktrees.lowerBound]) }
        let superset = home + "/.superset/worktrees/"
        if path.hasPrefix(superset), let repo = path.dropFirst(superset.count).split(separator: "/").first { return String(repo) }
        if path.hasPrefix(home + "/.superset/sessions/") { return supersetSessions }
        if path == home || path == home + "/" { return "~" }
        return (path as NSString).lastPathComponent
    }

    private static func isTemporary(_ folder: String) -> Bool {
        ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"].contains { folder == $0 || folder.hasPrefix($0 + "/") }
    }
}
