import Foundation

/// The way a message from the phone reaches a session.
enum SendRoute: Equatable {
    /// Superset's own command, by the workspace and terminal it names.
    case superset(workspace: String, terminal: String)
    /// Typed into the session's tab in Terminal, iTerm2 or Ghostty.
    case tab(TabPlace)
    /// Every other terminal: the message waits for Claude's Stop hook to pick it up.
    case stopHook

    static let supersetTerminal = "SUPERSET_TERMINAL_ID"

    /// The route for an app with this bundle id. `environment` and `tab` are asked only
    /// by the apps that need them.
    static func route(bundleID: String?, environment: (String) -> String?, tab: () -> TabPlace?) -> SendRoute {
        if bundleID == OwnerApp.supersetBundle {
            // Both ids go into a command: they are ids and nothing else, or the hook is used.
            guard let workspace = environment(OwnerApp.supersetWorkspace), OwnerApp.isID(workspace),
                  let terminal = environment(supersetTerminal), OwnerApp.isID(terminal) else { return .stopHook }
            return .superset(workspace: workspace, terminal: terminal)
        }
        if TabPlace.terminal(bundleID: bundleID) != nil, let place = tab() { return .tab(place) }
        return .stopHook
    }
}

/// What it takes to tell one session something: its process, the way, and whether it waits on the person.
struct SessionReach: Equatable {
    /// A daemon-backed session can use its Stop hook without owning a terminal process.
    let process: SessionProcess?
    let route: SendRoute
    let waitingOnPerson: Bool
}
