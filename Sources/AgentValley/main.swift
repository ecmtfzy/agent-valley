import AppKit
import Combine

// Claude Code runs `AgentValley crew status` every few seconds: a command answers and exits
// before any of the app is touched, so it stays quick and never puts a second notch on screen.
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "crew" {
    exit(Crew.run(Array(CommandLine.arguments.dropFirst(2))))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let store = AgentStore()
    private let limits = PlanLimitsClient()
    private let answers = AnswerStore()
    private let usage = UsageLedger()
    private var updates: Updates!
    private var notch: NotchWindowController?
    private var watches = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First, before the answers socket or anything else of this copy is set up.
        AppPlace.quitOtherCopies()
        let misplaced = AppPlace.needsMove()
        if misplaced, AppPlace.offerMove() { return }
        // Both fire once now with the stored value, then again on every change.
        settings.$keepFinishedMinutes
            .sink { [store] minutes in store.setVisibleFor(TimeInterval(minutes * 60)) }
            .store(in: &watches)
        settings.$planLimits
            .sink { [limits] on in limits.setEnabled(on) }
            .store(in: &watches)
        settings.$answers
            .sink { [answers] on in answers.setEnabled(on); answers.checkPlugin() }
            .store(in: &watches)
        settings.$goToTab
            .sink { [store] on in store.setTabs(on) }
            .store(in: &watches)
        settings.$tokenUse
            .sink { [usage] on in usage.setEnabled(on) }
            .store(in: &watches)
        // Each time the transcripts move, requests find their rows and answered ones are withdrawn.
        store.$sessions
            .sink { [answers] sessions in answers.reconcile(with: sessions) }
            .store(in: &watches)
        // After an update the font the person installed is replaced with the one in this app,
        // and Ghostty's font line, where install put one, covers all of its faces. Not from a
        // copy that goes with the dmg: it may be older than the one in Applications.
        if !misplaced, let bundled = Bundle.main.resourceURL?.appendingPathComponent(CrewFont.fileName) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            CrewSetup.refreshGhosttyLine(home: home, environment: ProcessInfo.processInfo.environment)
            CrewSetup.refreshFont(home: home, bundled: bundled)
        }
        // Open at login follows the app to a new folder, never to one that goes with the dmg.
        if !misplaced { LoginItem.follow(settings) }
        updates = Updates()
        store.start()
        notch = NotchWindowController(store: store, settings: settings, limits: limits, answers: answers, sound: SoundPlayer(settings: settings), usage: usage, updates: updates)
    }
}

extension AppDelegate {
    /// Quitting ends every request without a decision and takes the socket file away.
    func applicationWillTerminate(_ notification: Notification) {
        answers.setEnabled(false)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
