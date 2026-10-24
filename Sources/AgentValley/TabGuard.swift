import Foundation

/// What the system says of a running process, read in one go.
struct ProcessFacts: Equatable {
    let tty: String?
    /// The process group the process is in.
    let group: Int32
    /// The process group in front on the process's terminal.
    let ttyGroup: Int32
    let startedAt: Date
}

/// A session's process, as first seen: the pid and when it started, so a reused pid is told apart.
struct SessionProcess: Equatable {
    let pid: Int32
    let startedAt: Date
}

enum TabGuard {
    /// True only while the session's own process is still the one in front on its terminal, so a
    /// shell or another program never gets typed into. Says nothing of which tab that is.
    static func claudeInFront(_ facts: ProcessFacts?, process: SessionProcess) -> Bool {
        guard let facts else { return false }
        return facts.startedAt == process.startedAt && facts.group == facts.ttyGroup
    }

    /// The same, and in the tab the message is meant for, so another tab never gets typed into.
    static func claudeHoldsTab(_ facts: ProcessFacts?, process: SessionProcess, place: TabPlace) -> Bool {
        guard let facts, claudeInFront(facts, process: process) else { return false }
        switch place.terminal {
        case .terminal, .iterm: return facts.tty == place.key
        // Ghostty tells no tty; its tab is found by folder.
        case .ghostty: return true
        }
    }
}
