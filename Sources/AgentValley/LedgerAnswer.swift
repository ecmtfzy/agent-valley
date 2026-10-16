import Foundation

/// What one answer used, as Claude Code's transcript records it, and where and by whom: one row
/// of the history.
struct LedgerAnswer: Equatable {
    var id: String
    var at: Date
    /// The folder the session worked in, as the line gives it. Empty when it gives none.
    var folder = ""
    var session = ""
    /// "main" for a session's own agent, or the sub-agent's type.
    var agent = "main"
    var model = ""
    var fast = false
    /// Run in the US only, which costs a tenth more.
    var us = false
    var input = 0
    /// Written to the cache to be kept five minutes, and an hour: priced apart.
    var write5m = 0
    var write1h = 0
    var read = 0
    var output = 0
    var searches = 0

    var tokens: Int { input + write5m + write1h + read + output }
    /// Every token that went in, the cache's included: what Haiku 5.5's price steps by.
    var prompt: Int { input + write5m + write1h + read }
}

extension LedgerAnswer {
    /// What an assistant line says its answer used. nil for any other line, and for one with no
    /// id, no time, or nothing used. `agent` is told by the file the line is in.
    init?(line: Data, agent: String) {
        // Cheap before dear: most lines of a transcript are not answers.
        guard line.range(of: Data("\"usage\"".utf8)) != nil,
              let object = SafeJSON.object(line),
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let id = message["id"] as? String, !id.isEmpty,
              let usage = message["usage"] as? [String: Any],
              let at = (object["timestamp"] as? String).flatMap(TranscriptReader.date(from:)) else { return nil }
        func count(_ value: Any?) -> Int { max(0, (value as? NSNumber)?.intValue ?? 0) }
        self.init(id: id, at: at, folder: object["cwd"] as? String ?? "", session: object["sessionId"] as? String ?? "",
                  agent: agent, model: message["model"] as? String ?? "")
        fast = usage["speed"] as? String == "fast"
        us = usage["inference_geo"] as? String == "us"
        input = count(usage["input_tokens"])
        if let split = usage["cache_creation"] as? [String: Any] {
            write5m = count(split["ephemeral_5m_input_tokens"])
            write1h = count(split["ephemeral_1h_input_tokens"])
        } else {
            // Older lines give one count for what was written to the cache, and not for how
            // long: taken as five minutes.
            write5m = count(usage["cache_creation_input_tokens"])
        }
        read = count(usage["cache_read_input_tokens"])
        output = count(usage["output_tokens"])
        searches = count((usage["server_tool_use"] as? [String: Any])?["web_search_requests"])
        guard tokens > 0 || searches > 0 else { return nil }
    }
}
