import Foundation

/// A bounded lifecycle receipt survives a new turn starting between two UI polls.
/// Contains no message, tool input, account data, or route for answering requests.
struct CodexTurnCompletion: Equatable {
    let turnID: String
    let startedAt: Date?
    let endedAt: Date

    static let limit = 8

    static func recording(_ receipt: Self, in previous: [Self]) -> [Self] {
        guard receipt.startedAt.map({ $0 <= receipt.endedAt }) ?? true else { return previous }
        return Array((previous.filter { $0.turnID != receipt.turnID } + [receipt])
            .sorted { ($0.endedAt, $0.turnID) < ($1.endedAt, $1.turnID) }.suffix(limit))
    }
}
