import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let store = AgentStore()
    private let limits = PlanLimitsClient()
    private let answers = AnswerStore()
    private let usage = UsageLedger()
    private var notch: NotchWindowController?
    private var watches = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Both fire once now with the stored value, then again on every change.
        settings.$keepFinishedMinutes
            .sink { [store] minutes in store.setVisibleFor(TimeInterval(minutes * 60)) }
            .store(in: &watches)
        settings.$planLimits
            .sink { [limits] on in limits.setEnabled(on) }
            .store(in: &watches)
        settings.$answers
            .sink { [answers] on in answers.setEnabled(on) }
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
        LoginItem.follow(settings)
        store.start()
        notch = NotchWindowController(store: store, settings: settings, limits: limits, answers: answers, sound: SoundPlayer(settings: settings), usage: usage)
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
