/// Which account owns the shared quota surfaces. The session namespace is stable;
/// model labels and window percentages are not evidence of the account being used.
struct PlanLimitsScope: Equatable {
    let primary: PlanLimitsProvider?
    let secondary: PlanLimitsProvider?
    /// A global scene or an unlabelled ring is meaningful only for one provider.
    let global: PlanLimitsProvider?

    init(sessionIDs: [String], claudeEnabled: Bool, codexEnabled: Bool) {
        primary = claudeEnabled ? .claude : codexEnabled ? .codex : nil
        secondary = claudeEnabled && codexEnabled ? .codex : nil

        let hasCodex = sessionIDs.contains { $0.hasPrefix("codex-") }
        let hasClaude = sessionIDs.contains { !$0.hasPrefix("codex-") }
        if hasClaude && hasCodex {
            global = nil
        } else if hasCodex {
            global = codexEnabled ? .codex : nil
        } else if hasClaude {
            global = claudeEnabled ? .claude : nil
        } else if claudeEnabled != codexEnabled {
            global = primary
        } else {
            global = nil
        }
    }

    static func display(for provider: PlanLimitsProvider?, claude: PlanLimitsClient.Display,
                        codex: PlanLimitsClient.Display) -> PlanLimitsClient.Display {
        switch provider {
        case .claude: return claude
        case .codex: return codex
        case nil: return .off
        }
    }
}
