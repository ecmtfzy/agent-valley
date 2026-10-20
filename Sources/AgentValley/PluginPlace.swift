import Foundation

/// Whether Claude Code's plugin list still points at this copy of the app. 0.1 lived in
/// /opt/homebrew; after its users install 0.2 in /Applications, their list still names the old
/// place, and Allow and Deny stop with nothing said. Read only: the app never writes into ~/.claude.
enum PluginPlace {
    static let marketplace = "agent-valley"
    /// The plugin inside this copy of the app.
    static var here: URL { (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("claude-plugin") }
    static let registry = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plugins/known_marketplaces.json")

    /// True when the list has this app's marketplace and it names a folder other than `plugin`
    /// that is gone. Another copy still there takes the plugin to the same socket, so it works.
    /// No list, no entry, or a list that cannot be read: not lost, there is nothing to fix.
    static func lost(_ registry: Data?, plugin: URL) -> Bool {
        guard let registry, let list = try? JSONSerialization.jsonObject(with: registry) as? [String: Any],
              let entry = list[marketplace] as? [String: Any] else { return false }
        let path = ((entry["source"] as? [String: Any])?["path"] as? String) ?? (entry["installLocation"] as? String)
        guard let path else { return false }
        return same(URL(fileURLWithPath: path)) != same(plugin) && !FileManager.default.fileExists(atPath: path)
    }

    private static func same(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
