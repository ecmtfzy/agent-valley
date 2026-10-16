import AppKit
import SwiftUI

/// What a card needs to show requests under its rows and to answer them.
struct AnswerContext {
    let requests: (_ row: String) -> [AnswerStore.Pending]
    /// How requests under a row ended a moment ago.
    let settled: (_ row: String) -> [AnswerStore.Settled]
    /// When a request's buttons start taking clicks, or nil while the panel is shut.
    let armsAt: (AnswerStore.Pending) -> Date?
    /// Whether something spanning these heights of the list is on screen from top to bottom.
    let inFullView: (_ minY: CGFloat, _ maxY: CGFloat) -> Bool
    /// Says whether the click counted.
    let answer: (UUID, Answer, _ clickAt: Date) -> Bool
    /// Told where a request sits in the list each time that changes, and nil when the view that
    /// drew it leaves. The second id is that view's own: a request can pass from one to another.
    let placed: (UUID, UUID, ClosedRange<CGFloat>?) -> Void
    /// Scrolls a request into full view.
    let reveal: (UUID) -> Void
    /// Told each time a request moves in the list.
    var moved: (UUID) -> Void = { _ in }
    /// Puts a request away, unanswered. Says whether the click counted.
    var hide: (UUID, _ clickAt: Date) -> Bool = { _, _ in false }
    /// The request the keys answer on this card: nil on every card but the one the arrow keys
    /// are on. For drawing the chords on its buttons, and nothing else.
    var keyTarget: UUID? = nil
    /// A key that was pressed for a request and did not count.
    var keyNote: KeyNote? = nil
}

/// One request under the row that owns it: what is asked, in full, and the buttons that answer it.
struct AnswerView: View {
    let item: AnswerStore.Pending
    /// What the session or agent is called, for VoiceOver.
    let title: String
    let armsAt: Date?
    let inFullView: (_ minY: CGFloat, _ maxY: CGFloat) -> Bool
    let answer: (Answer, _ clickAt: Date) -> Bool
    var placed: (UUID, ClosedRange<CGFloat>?) -> Void = { _, _ in }
    var reveal: () -> Void = {}
    /// The app the session runs in, for a request that has to be answered there.
    var owner: OwnerApp?
    /// A click on one of its buttons did not count a moment ago: it says so beside them.
    @State private var refused = false
    /// Counts those clicks, so the same one refused again is said again for its full time.
    @State private var refusals = 0
    /// Why it did not count: the request was not all in view, or the list had just moved.
    @State private var refusedCut = false
    /// The keys answer this request: its buttons carry the chords that fire them.
    var isKeyTarget = false
    /// A key was pressed for this request and did not count: whether because it was cut.
    var keyRefused: Bool? = nil
    /// When this request last moved in the list. Its buttons look dead for a moment after, as
    /// the store treats them.
    @State private var movedAt = Date.distantPast
    /// Told each time the request moves.
    var moved: () -> Void = {}
    /// Puts the request away, unanswered. Says whether the click counted.
    var hide: (_ clickAt: Date) -> Bool = { _ in false }
    /// This view's own id, so only it can take back the place it reported.
    @State private var token = UUID()
    /// Only how the buttons look. Whether a click counts is decided by the store when it happens.
    @State private var armed = false
    /// Where the request sits in the list. A request cut by the list's edge or under its fade is
    /// not all there to read, so its buttons take no click.
    /// Before its place is known it is nowhere, and that is not in view.
    @State private var span: ClosedRange<CGFloat> = -1...(-1)
    /// Leaves for the session's app, by the panel's rule about when such a click counts.
    @Environment(\.goTo) private var leave

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.hidden {
                // Put away: what it is, and where it is answered now.
                Text(verbatim: item.ask.summary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                note(Format.terminalOnly)
                goTo(filled: true)
            } else {
                switch item.ask.kind {
                case .permission(let shown):
                    // All of it, never cut: this is what the person is agreeing to.
                    whole(Text(verbatim: item.ask.tool).bold())
                    VStack(alignment: .leading, spacing: 2) {
                        if let command = shown.command { whole(Text(verbatim: command)) }
                        fields(shown.fields)
                    }
                    // Apart: neither answer can be taken back, and a slip of 8 points was all it took.
                    // Neither is drawn as the one to pick: the app does not answer for the person.
                    footer {
                        button(.allow, "Allow once", key: .allow)
                        button(.deny, "Deny", key: .deny)
                    }
                case .permissionHidden(let partial):
                    Text(verbatim: item.ask.toolTitle).bold()
                    // Enough to tell which request this is, such as the file. Not enough to allow it.
                    VStack(alignment: .leading, spacing: 2) {
                        fields(partial.fields)
                        ForEach(Array(partial.named.enumerated()), id: \.offset) { _, name in
                            // Dim throughout: nothing on this line is a value.
                            whole(Text(verbatim: name + ": " + Format.notShown).foregroundColor(.white.opacity(0.6)))
                        }
                    }
                    note(Format.cannotShow)
                    footer {
                        // First, and filled: the terminal is where this one can be agreed to. Alone,
                        // "Deny" read as the answer the panel recommends.
                        goTo(filled: true)
                        button(.deny, "Deny", key: .deny)
                    }
                case .question(let text, let header, let options):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !header.isEmpty {
                            // The question's own label for itself, set off from the question.
                            Text(verbatim: header).font(CardStyle.aside).bold().padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                                .fixedSize()
                        }
                        whole(Text(verbatim: text))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        // By position, never by label: hook text must not become a view identity.
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            optionRow(index + 1, option)
                        }
                    }
                    footer { button(.skip, "Skip", key: .deny) }
                case .terminalOnly(let text):
                    Text(verbatim: text).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    note(Format.terminalOnly)
                    goTo(filled: true)
                }
            }
        }
        .padding(.top, 4)
        .onGeometryChange(for: ClosedRange<CGFloat>.self) { proxy in
            let frame = proxy.frame(in: .scrollView)
            return frame.minY...max(frame.minY, frame.maxY)
        } action: {
            span = $0
            placed(token, $0)
            // Wherever it was a moment ago, a click on its way was aimed at what stood there.
            movedAt = Date()
            moved()
        }
        .onDisappear { placed(token, nil) }
        // "Go to" arriving beside "Deny" moves that button along its line.
        .onChange(of: owner?.name) { _, _ in
            movedAt = Date()
            moved()
        }

        // Said for a moment and taken back: by then the buttons take clicks again.
        .task(id: refusals) {
            guard refused else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { refused = false }
        }
        .task(id: [armsAt ?? .distantFuture, movedAt]) {
            armed = false
            guard let armsAt else { return }
            let wait = max(armsAt, movedAt.addingTimeInterval(AnswerStore.armAfter)).timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            if !Task.isCancelled { armed = true }
        }
    }

    private func fields(_ fields: [Ask.Shown.Field]) -> some View {
        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
            // Field names are dim and values are not, so a line inside a value
            // cannot be taken for a field of its own.
            whole(Text(verbatim: field.name + ": ").foregroundColor(.white.opacity(0.6)) + Text(verbatim: field.value))
        }
    }

    private func whole(_ text: Text) -> some View {
        text.lineLimit(nil).fixedSize(horizontal: false, vertical: true)
    }

    /// The answers on one line, apart, and at its far end the way to put the request away. A
    /// click or a key that did not count is said in that button's place, for its moment: the
    /// line has no room for both, and nothing below it moves.
    private func footer<Answers: View>(@ViewBuilder _ answers: () -> Answers) -> some View {
        HStack(spacing: 16) {
            answers()
            if refused || keyRefused != nil {
                notCounted
            } else {
                Spacer(minLength: 0)
                Button {
                    // A click of the mouse, and not one on its way before the request stood
                    // here: put away, it does not come back.
                    guard NotchPanel.handlingClick else { return }
                    refused = !hide(Self.clickTime())
                    refusedCut = false
                    refusals += 1
                } label: {
                    Text(verbatim: Format.hideRequest).foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 6).frame(height: 24).contentShape(Rectangle()).hoverFill()
                }
                .buttonStyle(.plain)
                .fixedSize()
                .opacity(armed ? 1 : 0.5)
                .help(Text(verbatim: Format.hideRequestHelp))
                .accessibilityHint(Text(verbatim: Format.hideRequestHelp))
            }
        }
    }

    /// One option, the whole row its button: its number, its label, and under that its own
    /// description, whole. An aim at its words is as far from the next option as the buttons
    /// were from each other.
    private func optionRow(_ number: Int, _ option: Ask.Option) -> some View {
        answerButton(.option(option.label), detail: option.detail) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Its place in the list, or the chord that picks it on the one request the keys
                // answer: which request that is must not be a guess.
                Text(verbatim: (isKeyTarget ? Format.chord(.option(number)) : nil) ?? "\(number).")
                    .foregroundStyle(.white.opacity(0.6)).frame(width: 18, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    whole(Text(verbatim: option.label))
                    if !option.detail.isEmpty { whole(Text(verbatim: option.detail).foregroundColor(.white.opacity(0.6))) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .hoverFill()
        }
    }

    /// One line, in room the buttons' own line already has: nothing below it moves.
    private var notCounted: some View {
        // Beside a wider button, as "Go to" with a long app's name is, it is set a little
        // smaller before it is cut.
        Text(verbatim: keyRefused.map { Format.notCounted(cut: $0, key: true) } ?? Format.notCounted(cut: refusedCut)).lineLimit(1).minimumScaleFactor(0.8)
    }

    /// The way to the app the session runs in, when that is known.
    @ViewBuilder
    private func goTo(filled: Bool) -> some View {
        if let owner {
            Button { leave(owner) } label: {
                Text(verbatim: Format.goTo(app: owner.name)).panelButton(filled: filled)
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text).foregroundStyle(.white.opacity(0.6)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }

    /// When the click now being handled was made. The action can run late on a busy main thread,
    /// and a click must be judged by when the finger went down.
    private static func clickTime() -> Date {
        NotchPanel.when(NotchPanel.pressedAt)
    }

    /// One answer, by a click or by its key, made at `at`. Not all in view is not all read:
    /// the answer is not sent, and the request is brought into view instead. One that came too
    /// soon after the list moved is not sent either. Both say so beside the buttons: they used
    /// to do nothing without a sign, and the person left thinking they had answered.
    private func press(_ choice: Answer, at: Date) {
        let whole = inFullView(span.lowerBound, span.upperBound)
        let counted = whole && answer(choice, at)
        refused = !counted
        refusedCut = !whole
        refusals += 1
        if !whole { reveal() }
    }

    private func button(_ choice: Answer, _ label: String, key: KeyCommand) -> some View {
        answerButton(choice) {
            HStack(spacing: 6) {
                Text(verbatim: label)
                // The chord that fires it, on the button itself, and only on the one request
                // the keys answer: which request that is must not be a guess.
                if isKeyTarget, let chord = Format.chord(key) { Text(verbatim: chord).foregroundStyle(.white.opacity(0.6)) }
            }
            .panelButton()
        }
        .fixedSize()
        // Neither answer can be taken back: what it sends is said before the click.
        .help(Text(verbatim: Format.answerHelp(choice) ?? ""))
    }

    /// What answers, whatever it looks like: a button, or an option's whole row.
    private func answerButton<Label: View>(_ choice: Answer, detail: String = "", @ViewBuilder label: () -> Label) -> some View {
        Button {
            // Whatever else may set a button's action off, only a click of the mouse counts as
            // one. The keys have their own way in, which names the request and the answer.
            guard NotchPanel.handlingClick else { return }
            press(choice, at: Self.clickTime())
        } label: {
            label()
        }
        .buttonStyle(.plain)
        // Dim for the moment after the list has moved. A request the edge cuts is not dimmed:
        // a click there counts for nothing either, but it brings the request into view and
        // says why.
        .opacity(armed ? 1 : 0.5)
        // The app's words, then the request's own, read apart.
        .accessibilityLabel(Text(verbatim: Format.answerLabel(choice)))
        .accessibilityValue(Text(verbatim: Format.answerValue(choice, tool: item.ask.toolTitle, title: title, detail: detail)))
        .accessibilityHint(Text(verbatim: Format.answerHint(choice)))
    }
}
