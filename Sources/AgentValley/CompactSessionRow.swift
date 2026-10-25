import SwiftUI

/// A session folded to one line, for when the full cards would not fit the panel: its agent,
/// its name, the step of whichever row moved last, the faces of the sub-agents at work and
/// how it is doing. Where it runs and which model are under the pointer.
struct CompactSessionRow: View {
    let card: SessionCard
    let motion: Motion
    var look = LeadLook()
    /// Puts the session away until it moves again. nil when there is nothing to put away.
    var hide: (() -> Void)?
    /// Keeps the hide button's place on a row that has none, so the columns stand in line.
    var reserveHide = false
    @Environment(\.goTo) private var goTo

    /// Sub-agents shown by face before the rest are counted.
    static let faces = 3

    var body: some View {
        let live = card.liveAgents()
        let step = Format.sessionStep(card)
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                SessionCardView.leadMascot(card, look: look, size: 16).frame(width: 20)
                // verbatim: the title is written by a model from the conversation and is untrusted.
                Text(verbatim: card.name).font(CardStyle.name).lineLimit(1).layoutPriority(1)
                if let step {
                    Text(verbatim: step).lineLimit(1).foregroundStyle(.white.opacity(0.6)).frame(minWidth: 96, alignment: .leading)
                }
                ForEach(live.prefix(Self.faces)) { row in
                    MascotView(status: row.status, kind: MascotKind(type: row.info.type), size: 14,
                               flag: MascotFlag(status: row.status), still: row.isStalled, activity: row.activity)
                }
                if live.count > Self.faces {
                    Text(verbatim: "+\(live.count - Self.faces)").foregroundStyle(.white.opacity(0.6)).fixedSize()
                }
                Spacer(minLength: 12)
                SessionCardView.CardStatusText(card: card).fixedSize()
            }
            // Read out as one thing; the hide button stays its own.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: [card.name, Format.cardStatus(card), step, Format.place(card)].compactMap { $0 }.joined(separator: ", ")))
            // A click anywhere on it goes to the session's app; so does pressing it from the keys.
            .accessibilityAddTraits(card.owner == nil ? [] : .isButton)
            .accessibilityHint(Text(verbatim: card.owner.map { Format.goTo(app: $0.name) } ?? ""))
            .accessibilityAction { if let owner = card.owner { goTo(owner) } }
            // What the row leaves out, under the pointer.
            .help(Text(verbatim: ([card.name, Format.place(card)] + [card.main?.info.model].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: "\n")))
            .goesTo(card.owner)
            if let hide {
                SessionCardView.HideButton(name: card.name, action: hide)
            } else if reserveHide {
                Color.clear.frame(width: 18, height: 1)
            }
        }
        .frame(height: ListFit.row)
        .padding(.horizontal, CardStyle.inset)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        // Faces come and go as sub-agents start and finish.
        .animation(motion.list, value: live.map(\.id))
    }
}
