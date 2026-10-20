import AppKit

/// Where this copy of the app runs from. Opened from the mounted dmg, or from a folder macOS runs
/// a downloaded app out of at random (App Translocation), it cannot update itself, and the
/// plugin's command names a path that is gone once the app quits.
enum AppPlace {
    /// `readOnlyVolume`: the disk it is on cannot be written to, as a mounted dmg cannot. A build
    /// on a disk of its own under /Volumes is left where it is.
    static func needsMove(_ bundlePath: String, readOnlyVolume: Bool) -> Bool {
        bundlePath.contains("/AppTranslocation/") || (bundlePath.hasPrefix("/Volumes/") && readOnlyVolume)
    }

    static func needsMove(_ bundle: URL = Bundle.main.bundleURL) -> Bool {
        needsMove(bundle.path, readOnlyVolume: (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false)
    }

    /// One copy runs at a time. Any other, an older version, one opened from the dmg, or one whose
    /// files brew already took away, holds the panel and the answers socket: it is asked to quit,
    /// and after 5 seconds made to. The socket's lock goes with its process.
    /// ponytail: a copy made to quit loses what it had not written yet; it had 5 seconds to.
    @MainActor static func quitOtherCopies() {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        wait(for: others, seconds: 5)
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        wait(for: others, seconds: 1)
    }

    @MainActor private static func wait(for apps: [NSRunningApplication], seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while apps.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    /// Copies `app` into `folder` and returns the copy. It is copied whole beside the one already
    /// there first; only then does the old one go to `trash` and the new one take its name. A copy
    /// that fails leaves the old one as it was.
    static func move(_ app: URL, into folder: URL, trash: (URL) throws -> Void) throws -> URL {
        let target = folder.appendingPathComponent(app.lastPathComponent)
        let part = folder.appendingPathComponent(".\(app.lastPathComponent).part")
        let files = FileManager.default
        try? files.removeItem(at: part)
        do {
            try files.copyItem(at: app, to: part)
            unquarantine(part)
            if files.fileExists(atPath: target.path) { try trash(target) }
            try files.moveItem(at: part, to: target)
        } catch {
            try? files.removeItem(at: part)
            throw error
        }
        return target
    }

    /// The copy keeps the downloaded dmg's quarantine flag. The person has already opened this very
    /// app; with the flag left on, macOS asks about the copy in Applications again and runs it
    /// from a random folder (App Translocation), where it offers the move once more.
    static func unquarantine(_ app: URL) {
        removexattr(app.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        guard let inside = FileManager.default.enumerator(atPath: app.path) else { return }
        for case let item as String in inside {
            removexattr(app.appendingPathComponent(item).path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }

    /// Asks once per launch. True when the copy in Applications has been opened and this one is
    /// quitting: the caller sets nothing else up.
    @MainActor static func offerMove(bundle: URL = Bundle.main.bundleURL) -> Bool {
        NSApp.activate()
        let ask = NSAlert()
        ask.messageText = Format.moveTitle
        ask.informativeText = Format.moveMessage
        ask.addButton(withTitle: Format.moveButton)
        ask.addButton(withTitle: Format.notNow)
        guard ask.runModal() == .alertFirstButtonReturn else { return false }
        // The copy that ran there quit as this one started (quitOtherCopies).
        let applications = URL(fileURLWithPath: "/Applications")
        let moved: URL
        do {
            moved = try move(bundle, into: applications) { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
        } catch {
            say(Format.moveFailed)
            return false
        }
        // Waited for: if the new copy does not open, this one stays running and says so.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        var opened: Bool?
        NSWorkspace.shared.openApplication(at: moved, configuration: configuration) { _, error in
            DispatchQueue.main.async { opened = error == nil }
        }
        while opened == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        guard opened == true else {
            say(Format.movedNotOpened)
            return false
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }

    @MainActor private static func say(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.runModal()
    }
}
