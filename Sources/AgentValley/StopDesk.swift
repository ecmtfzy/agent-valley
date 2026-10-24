import Combine
import Foundation

enum DeskDelivery: Equatable { case sent, waitingForTurnEnd }

struct LeftOver: Identifiable, Equatable {
    let id: UUID
    let session: String
    let text: String
}

/// Holds Stop hooks while the owner is Away and hands them the phone's words.
/// Main thread only. A hook leaves the table before its reply runs, so it is answered once.
final class StopDesk: ObservableObject {
    var awayOn = false
    var holds: (String) -> Bool = { _ in false }
    var onSent: ([UUID]) -> Void = { _ in }
    var onBackAtDesk: ([UUID]) -> Void = { _ in }
    @Published private(set) var leftOver: [LeftOver] = []

    private struct Held {
        let id: UUID
        let reply: (Data?) -> Bool
    }

    private var held: [String: Held] = [:]
    private var pending: [LeftOver] = []   // queued messages, arrival order
    private var releases = 0

    @discardableResult
    func arrived(_ stop: StopWait, reply: @escaping (Data?) -> Bool) -> UUID {
        let hook = UUID()
        if let old = held.removeValue(forKey: stop.session) { _ = old.reply(nil) }
        guard awayOn, holds(stop.session) else {
            _ = reply(nil)
            return hook
        }
        held[stop.session] = Held(id: hook, reply: reply)
        flush(stop.session)
        return hook
    }

    func hookGone(_ hook: UUID) {
        if let session = held.first(where: { $0.value.id == hook })?.key { held[session] = nil }
    }

    func deliver(id: UUID, session: String, text: String) -> DeskDelivery {
        guard !pending.contains(where: { $0.id == id }) else { return .waitingForTurnEnd }
        pending.append(LeftOver(id: id, session: session, text: text))
        return flush(session) ? .sent : .waitingForTurnEnd
    }

    func release() {
        releases += 1
        let hooks = Array(held.values)
        held = [:]
        for hook in hooks { _ = hook.reply(nil) }
        backAtDesk(pending)
        pending = []
    }

    func dismiss(_ id: UUID) {
        leftOver.removeAll { $0.id == id }
    }

    private func backAtDesk(_ items: [LeftOver]) {
        guard !items.isEmpty else { return }
        leftOver += items
        onBackAtDesk(items.map(\.id))
    }

    /// Sends the session's queue through its held hook. True only when it was sent.
    @discardableResult
    private func flush(_ session: String) -> Bool {
        let items = pending.filter { $0.session == session }
        guard let hook = held[session], !items.isEmpty else { return false }
        held[session] = nil
        pending.removeAll { $0.session == session }   // out of the queue before the reply, so a re-entrant call cannot take them twice
        let before = releases
        guard hook.reply(AnswerProtocol.block(reason: items.map(\.text).joined(separator: "\n\n"))) else {
            if releases == before { pending = items + pending } else { backAtDesk(items) }
            return false
        }
        onSent(items.map(\.id))
        return true
    }
}
