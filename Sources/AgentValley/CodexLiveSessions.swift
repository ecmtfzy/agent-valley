import Foundation

/// Disk discovery and rollout parsing never block the shared session store queue.
/// Only one refresh may run at a time; callers receive the last finished snapshot.
final class CodexLiveSessions {
    private let lock = NSLock()
    private var snapshot: [SessionCard] = []
    private var refreshing = false
    private let read: (Date, TimeInterval, Set<String>) -> [SessionCard]
    private let schedule: (@escaping () -> Void) -> Void

    convenience init(reader: CodexLiveRollouts) {
        let worker = DispatchQueue(label: "agent-valley.codex-live-rollouts", qos: .utility)
        self.init(read: { reader.readCards(now: $0, visibleFor: $1, excluding: $2) },
                  schedule: { worker.async(execute: $0) })
    }

    init(read: @escaping (Date, TimeInterval, Set<String>) -> [SessionCard],
         schedule: @escaping (@escaping () -> Void) -> Void) {
        self.read = read
        self.schedule = schedule
    }

    func cards(now: Date, visibleFor: TimeInterval, excluding: Set<String>) -> [SessionCard] {
        lock.lock()
        let cached = snapshot
        let shouldRefresh = !refreshing
        if shouldRefresh { refreshing = true }
        lock.unlock()

        if shouldRefresh {
            schedule { [weak self] in
                guard let self else { return }
                let updated = self.read(now, visibleFor, excluding)
                self.lock.lock()
                self.snapshot = updated
                self.refreshing = false
                self.lock.unlock()
            }
        }

        // Hooks may arrive while a read is running. Apply current exclusions and age
        // the cached rows here, so a slow read cannot duplicate or keep a stale card alive.
        return cached.compactMap { original in
            guard !excluding.contains(original.id), let row = original.main,
                  let activity = row.info.lastActivity,
                  now.timeIntervalSince(activity) < AgentStore.forgetAfter,
                  row.status != .done || now.timeIntervalSince(activity) < max(0, visibleFor) else { return nil }
            var card = original
            card.main = AgentRow(id: row.id, info: row.info, status: row.status,
                                 elapsed: max(0, (row.status == .done ? activity : now)
                                    .timeIntervalSince(row.info.turnStartedAt ?? activity)),
                                 quietFor: row.status == .done ? 0 : max(0, now.timeIntervalSince(activity)),
                                 calledBusy: row.calledBusy)
            return card.asShown
        }
    }
}
