import AppKit
import Sparkle

/// Updates for the signed releases, through Sparkle. Only a release's Info.plist says where they
/// are: a build to work on the app has no feed, never starts Sparkle, and never replaces itself
/// with a release.
final class Updates: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    /// The version a check on its own found, while the person has not seen it yet. The app has
    /// no Dock icon, and Sparkle keeps a window of its own from taking the keys someone is typing
    /// with, so it may wait behind other windows: the panel says it is there.
    @Published private(set) var waiting: String?
    let isAvailable: Bool
    private var controller: SPUStandardUpdaterController!

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        isAvailable = Self.isConfigured(info)
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        if isAvailable { controller.startUpdater() }
    }

    static func isConfigured(_ info: [String: Any]) -> Bool {
        !((info["SUFeedURL"] as? String) ?? "").isEmpty && !((info["SUPublicEDKey"] as? String) ?? "").isEmpty
    }

    var checksAutomatically: Bool {
        get { isAvailable && controller.updater.automaticallyChecksForUpdates }
        set {
            guard isAvailable else { return }
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    /// Called as Sparkle's window is about to come up at the person's asking. The panel would
    /// otherwise stay over its top half; it gets out of the way, as a menu does.
    var willShowWindow: (() -> Void)?

    func checkNow() {
        guard isAvailable else { return }
        willShowWindow?()
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// Brings the window of the update that waits to the front, as Sparkle does for a check asked for.
    func show() { checkNow() }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Never on its own: Sparkle's "immediate focus" includes the minute after launch, at login
    /// too, when the person may be typing. The panel's line says it is there; Have a look shows it.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !state.userInitiated { waiting = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        waiting = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        waiting = nil
    }
}
