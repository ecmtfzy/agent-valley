import AppKit
import SwiftUI
import XCTest
@testable import AgentValley

/// Draws the real panel in a window off the screen and saves what it looks like, and what a
/// screen reader is told of it. Not a test of anything: it passes whatever it draws, and is
/// skipped unless `testing/pictures.sh` runs it, which also makes the sessions it shows.
///
/// For looking at a change while the owner works on this Mac: it moves no pointer, presses no
/// key and puts nothing on the screen. It is not a click or a key on the panel itself, and what
/// was checked this way should be said to have been checked this way.
/// Hands the panel the same plan limits every time it asks.
private struct FixedLimits: PlanLimitsSource {
    let limits: PlanLimits

    func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void {
        done(.success(limits))
        return {}
    }
}

@MainActor
final class PanelPicturesTests: XCTestCase {
    private var host: NSHostingView<PanelView>!
    private var out = ""
    private var scene = ""
    private var shots = 0

    /// Lets the panel draw, animate and scroll for a while: all of that happens on this thread.
    private func pump(_ seconds: TimeInterval = 1.2) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func name(_ what: String) -> String {
        shots += 1
        return "\(out)/\(scene)-\(shots)-\(what)"
    }

    private func picture(_ what: String, after wait: TimeInterval = 1.2) {
        pump(wait)
        host.layoutSubtreeIfNeeded()
        guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: image)
        try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name(what) + ".png"))
    }

    /// A click at a point of the panel, measured from its top left in points, sent to its window.
    private func click(atTopLeftOffset point: CGPoint) {
        guard let window = host.window else { return }
        let at = host.convert(NSPoint(x: point.x, y: host.isFlipped ? point.y : host.bounds.height - point.y), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
            pump(0.1)
        }
    }

    /// Scrolls the panel's list, or the page in its place, to its foot, as a wheel would.
    private func scrollToEnd() {
        func find(_ view: NSView) -> NSScrollView? {
            (view as? NSScrollView) ?? view.subviews.lazy.compactMap(find).first
        }
        guard let scroll = find(host), let document = scroll.documentView else { return }
        let end = NSPoint(x: 0, y: document.isFlipped ? max(0, document.frame.height - scroll.contentView.bounds.height) : 0)
        scroll.contentView.scroll(to: end)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// What a screen reader is told, asked from outside as one asks: SwiftUI only builds that
    /// tree for a client that comes through the system. The answers come from this thread, so
    /// it has to keep turning while the tool asks.
    private func spoken(_ what: String) {
        pump()
        guard let tool = ProcessInfo.processInfo.environment["PANEL_PICTURES_AXDUMP"] else { return }
        let path = name(what) + ".txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["\(getpid())"]
        process.standardOutput = FileHandle(forWritingAtPath: path)
        guard (try? process.run()) != nil else { return }
        while process.isRunning { pump(0.05) }
    }

    /// A ledger switched on over one answer of ten minutes ago, with what it has counted already out.
    private func countedLedger(in folder: String) throws -> UsageLedger {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = #"{"type":"assistant","timestamp":"\#(stamp.string(from: Date().addingTimeInterval(-600)))","cwd":"/Users/demo/shop-web","sessionId":"s1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":2000,"cache_creation_input_tokens":420000,"cache_read_input_tokens":3100000,"output_tokens":96400}}}"#
        let file = URL(fileURLWithPath: folder + "/projects/p/s1.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
        let ledger = UsageLedger(root: URL(fileURLWithPath: folder + "/projects"), database: URL(fileURLWithPath: folder + "/history.sqlite"))
        ledger.setEnabled(true)
        for _ in 0..<50 where ledger.summary == nil { pump(0.1) }
        return ledger
    }

    /// A ledger over a made-up month so far: four projects, one with a sub-agent, at steady hours.
    /// A project's name and a session's are too long for the panel, to see them cut.
    private func madeUpLedger(in folder: String) throws -> UsageLedger {
        let root = URL(fileURLWithPath: folder + "/projects")
        let now = Date()
        let start = HistoryReport.calendar().dateInterval(of: .month, for: now)!.start
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let projects = [("shop-web", "Checkout with refunds, webhooks, receipt emails and a retry queue for payments", "claude-opus-5-5"), ("api", "Rate limits for the public API", "claude-opus-5-5"),
                        ("agents-visualizer", "History in the notch", "claude-sonnet-5-5"), ("warehouse-inventory-sync-service-backend-and-admin-dashboard-v2", "Nightly stock import", "claude-haiku-5-5")]
        for (index, project) in projects.enumerated() {
            let session = "session-\(index)"
            var lines = [#"{"type":"ai-title","aiTitle":"\#(project.1)","sessionId":"\#(session)"}"#]
            var sub: [String] = []
            var at = start.addingTimeInterval(Double(9 + index) * 3600)
            var n = 0
            while at < now {
                let output = 20_000 + (n * 7919 + index * 104_729) % 90_000
                let answer = #"{"type":"assistant","timestamp":"\#(stamp.string(from: at))","cwd":"\#(NSHomeDirectory())/.superset/worktrees/\#(project.0)/ws","sessionId":"\#(session)","message":{"id":"m-\#(index)-\#(n)","model":"\#(project.2)","usage":{"input_tokens":12,"cache_read_input_tokens":80000,"output_tokens":\#(output)}}}"#
                if index == 0, n % 3 == 0 { sub.append(answer) } else { lines.append(answer) }
                at = at.addingTimeInterval(Double(5 + (n * 13 + index * 7) % 11) * 3600)
                n += 1
            }
            let file = root.appendingPathComponent("p\(index)/\(session).jsonl")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            if !sub.isEmpty {
                let agent = root.appendingPathComponent("p\(index)/\(session)/subagents/agent-a1.jsonl")
                try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
                try (sub.joined(separator: "\n") + "\n").write(to: agent, atomically: true, encoding: .utf8)
                try #"{"agentType":"Explore","description":"Find the payment code"}"#.write(
                    to: root.appendingPathComponent("p\(index)/\(session)/subagents/agent-a1.meta.json"), atomically: true, encoding: .utf8)
            }
        }
        let ledger = UsageLedger(root: root, database: URL(fileURLWithPath: folder + "/history.sqlite"))
        _ = ledger.scan(now: now)
        return ledger
    }

    func testDrawThePanelOffTheScreen() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let home = environment["PANEL_PICTURES_HOME"], let out = environment["PANEL_PICTURES_OUT"] else {
            throw XCTSkip("Run by testing/pictures.sh, which makes the sessions to draw.")
        }
        self.out = out
        scene = environment["PANEL_PICTURES_SCENE"] ?? "list"
        // An app as far as the system is concerned: without that it serves no accessibility tree.
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()

        let root = URL(fileURLWithPath: home + "/.claude/projects")
        let store = AgentStore(root: root)
        let settings = Settings(defaults: throwawayDefaults())
        let answers = AnswerStore(directory: URL(fileURLWithPath: home + "/answers"))
        let state = NotchState()
        // A 14-inch MacBook's screen and notch: the panel sizes itself by them.
        state.screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        state.barHeight = 38
        state.notchWidth = 200
        store.start()
        pump(1.5)
        // The token line shows once something is counted, and demo.py's answers carry no ids: for
        // its scene, a ledger over a made-up answer of its own.
        let usage = scene == "tokens" ? try countedLedger(in: home + "/tokens")
            : scene.hasPrefix("history") ? try madeUpLedger(in: home + "/history")
            : UsageLedger(root: root, database: URL(fileURLWithPath: home + "/history.sqlite"))
        // For the update scene, a release's: its About page has the Updates box. Never started.
        let updates = scene == "update" ? Updates(info: ["SUFeedURL": "https://example.invalid/appcast.xml", "SUPublicEDKey": "k"], starts: false)
            : Updates(info: [:])
        // For the fishing scenes, a plan limit that has run out: the 5-hour one, or the weekly one.
        // Their signs' pictures from the repo: here there is no app bundle to find them in.
        let limits: PlanLimitsClient
        if scene.hasPrefix("fishing") {
            SignArt.folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("signs")
            // On the hour, as the plan's windows reset.
            let hour = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / 3600).rounded(.up) * 3600)
            let soon = hour.addingTimeInterval(2 * 3600), later = hour.addingTimeInterval(3 * 86400)
            limits = PlanLimitsClient(source: FixedLimits(limits: scene == "fishing-week"
                ? PlanLimits(fiveHour: PlanLimit(usedPercent: 12, resetsAt: soon), week: PlanLimit(usedPercent: 100, resetsAt: later))
                : PlanLimits(fiveHour: PlanLimit(usedPercent: 100, resetsAt: soon), week: PlanLimit(usedPercent: 64, resetsAt: later))))
            limits.setEnabled(true)
        } else {
            limits = PlanLimitsClient()
        }
        let desk = StopDesk()
        // Its Away flag goes in a folder of its own, never beside the running app's socket.
        let awayFolder = FileManager.default.temporaryDirectory.appendingPathComponent("pictures-away-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: awayFolder) }
        let away = AwayWatch(desk: desk, folder: awayFolder, lastInput: { .distantPast })
        host = NSHostingView(rootView: PanelView(store: store, state: state, settings: settings, limits: limits, answers: answers,
                                                 sound: SoundPlayer(settings: settings), usage: usage, updates: updates,
                                                 away: away, desk: desk))
        // Far to the left of any display. In the window list, so that it draws and animates.
        let window = NSWindow(contentRect: CGRect(x: -4000, y: 0, width: 600, height: 960), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .darkGray
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        func list() -> SessionList {
            AgentStore.arrange(AgentStore.ordered(AgentStore.showing(answers.overlay(store.sessions), hidden: state.hidden), by: settings.grouping),
                               idle: settings.idleSessions, keeping: answers.settledSessions)
        }
        func walked() -> [String] { list().walked(idleExpanded: state.idleExpanded).map(\.id) }
        func open() {
            state.expanded = true
            state.openedAt = Date()
            state.opens += 1
        }

        switch scene {
        case "list":
            open()
            picture("open")
        case "status":
            settings.grouping = .status
            open()
            picture("grouped")
        case "keys":
            // The ring on each session in turn, down the list and back, in both orders.
            for grouping in [Grouping.projects, .status] {
                settings.grouping = grouping
                open()
                state.keyboard = true
                state.selected = KeyCommand.start(in: list().cards)
                picture("\(grouping.rawValue)-start")
                for step in 1...walked().count {
                    state.selected = KeyCommand.move(state.selected, by: 1, in: walked())
                    picture("\(grouping.rawValue)-down\(step)")
                }
                state.selected = KeyCommand.move(state.selected, by: -1, in: walked())
                picture("\(grouping.rawValue)-up")
            }
        case "idle":
            open()
            state.keyboard = true
            state.idleExpanded = true
            pump()
            state.selected = walked().last
            picture("ring-on-idle")
        case "intro":
            state.introducing = true
            open()
            picture("first-launch")
        case "legend":
            open()
            state.showingLegend = true
            for tab in LegendTab.allCases {
                state.legendTab = tab
                picture(tab.rawValue)
            }
        case "settings":
            open()
            // Two displays, the bigger one picked, as in issue #1.
            state.displays = [DisplayChoice(id: "built-in", name: "Built-in Retina Display"), DisplayChoice(id: "dell", name: "DELL U2720Q")]
            settings.display = "dell"
            state.showingSettings = true
            for tab in SettingsTab.allCases {
                state.settingsTab = tab
                picture(tab.rawValue)
            }
            // General at its foot: the Display list.
            state.settingsTab = .general
            pump()
            scrollToEnd()
            picture("general-scrolled")
            // The page the plugin's command is on, with its switch on.
            settings.answers = true
            state.settingsTab = .claudeCode
            picture("claude-code-answering")
            // Scrolled to its foot: the way back and the pages stay at the top.
            scrollToEnd()
            picture("claude-code-scrolled")
            // And a click on a page there still lands on it. A click sent to the window: the
            // pointer does not move.
            click(atTopLeftOffset: CGPoint(x: 518, y: 91))
            picture("about-after-click")
        case "request":
            // What the plugin's hook would send for two of the made-up sessions, handed straight
            // to the store: a command to allow, then a question with options.
            func ask(_ title: String, tool: String, input: [String: Any]) throws -> SessionCard {
                let card = try XCTUnwrap(store.sessions.first { $0.name == title })
                let hook: [String: Any] = ["tool_name": tool, "tool_input": input, "transcript_path": card.id + ".jsonl"]
                answers.add(try XCTUnwrap(Ask(hookInput: JSONSerialization.data(withJSONObject: hook)))) { _ in true }
                answers.reconcile(with: store.sessions)
                return card
            }
            open()
            let deploy = try ask("Deploy preview build", tool: "Bash", input: ["command": "git push origin preview", "description": "Push the preview branch"])
            picture("command")
            state.keyboard = true
            state.selected = deploy.id
            picture("command-with-keys")
            // A key pressed the moment the list has moved: what the buttons' line says of it.
            answers.noteLayoutChange()
            state.press(.allow, at: Date())
            picture("key-too-soon", after: 0.5)
            pump(2)
            state.press(.allow, at: Date())
            picture("allowed")
            state.keyboard = false
            state.selected = nil
            _ = try ask("Fix flaky login test", tool: "AskUserQuestion", input: ["questions": [[
                "question": "The login test fails only on CI. Which fix do you want?", "header": "Fix", "multiSelect": false,
                "options": [["label": "Retry the request", "description": "Up to three times"], ["label": "Mock the clock", "description": "No real waiting in the test"],
                            ["label": "Skip on CI", "description": "Keep it for local runs"]],
            ]]])
            picture("question")
        case "oldcopy":
            // 0.1 from Homebrew left behind: the line in the list, then the page its Fix it opens.
            updates.lookForOldCopy([home])
            // The sessions put away, so that the line at the foot of the list is in sight.
            for card in store.sessions { state.hidden[card.id] = Date() }
            open()
            picture("line")
            state.showingSettings = true
            state.settingsTab = .about
            picture("settings")
        case "update":
            // A version that came in on its own: the dot on the gear, the About tab and its line.
            updates.waiting = "0.3.4"
            open()
            picture("gear")
            spoken("gear")
            state.showingSettings = true
            state.settingsTab = .general
            picture("tabs")
            state.settingsTab = .about
            picture("about")
            spoken("about")
            // Looked at: every dot goes.
            updates.waiting = nil
            picture("about-looked")
        case "tokens":
            // The sessions put away, so that the line at the foot of the list is in sight.
            for card in store.sessions { state.hidden[card.id] = Date() }
            open()
            picture("line")
            spoken("line")
        case "history", "history-project":
            state.showingHistory = true
            state.historyPick = HistoryPick(project: scene == "history-project" ? "shop-web" : nil)
            open()
            picture("page")
            spoken("page")
        case "away":
            // One phone message that did not go, through the desk's own path, then Away on.
            _ = desk.deliver(id: UUID(), session: "demo", text: "Run the tests again and tell me what failed. Use `swift test`, not **npm**.")
            desk.release()
            away.phoneLinked = true
            away.buttonShown = true
            away.turnOn(.phoneButton)
            open()
            picture("open")
            spoken("open")
        case "fishing", "fishing-week":
            // Everyone done for now, so that the bar has the fish and the sign hangs over an empty list.
            for card in store.sessions { state.hidden[card.id] = Date() }
            picture("shut")
            open()
            // demo.py may have started more sessions meanwhile: those go too.
            for card in store.sessions { state.hidden[card.id] = Date() }
            picture("open")
            spoken("open")
            // Then over the sessions, back in the list.
            state.hidden = [:]
            picture("over-list")
        case "reader":
            open()
            spoken("list-open")
            state.keyboard = true
            state.selected = walked().dropFirst(2).first
            spoken("ring-on-third")
            state.keyboard = false
            state.selected = nil
            state.showingSettings = true
            spoken("settings-open")
            state.expanded = false
            state.openedAt = nil
            spoken("shut-from-settings")
            state.showingSettings = false
            spoken("shut")
        default:
            XCTFail("No scene called \(scene). See testing/pictures.sh.")
        }
    }
}
