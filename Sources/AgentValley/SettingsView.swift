import AppKit
import ServiceManagement
import SwiftUI

/// The pages of the settings: one long page had grown to twenty rows, and four pages split it
/// until two of them held a row or two. Two since 2026-10-15.
enum SettingsTab: String, CaseIterable {
    /// What the list shows, the sounds, and the app itself, with the way out at the end.
    case general
    /// What a click or a key does, and what reaches outside the app.
    case actions

    /// The word on its tab.
    var label: String { rawValue.capitalized }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var answers: AnswerStore
    @ObservedObject var limits: PlanLimitsClient
    @ObservedObject var updates: Updates
    /// Why the shortcut does nothing although it is switched on, when that is so.
    var shortcutNote: String? = nil
    /// The page shown. Kept by the panel, which also sends the person to a row on one.
    @Binding var tab: SettingsTab
    /// Back to the agents.
    let back: () -> Void
    /// The command last copied, so its button can say so for a moment.
    @State private var copied: String?
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                // The way back, in words: the gear that led here is the only other one.
                BackToAgents(action: back)
                Spacer(minLength: 0)
                PageTabs(title: "Settings pages", pages: SettingsTab.allCases, label: { $0.label }, selection: $tab)
            }
            switch tab {
            case .general:
                if updates.oldCopyLeft { oldCopy }
                list
                sounds
                app
            case .actions: actions
            }
        }
        .padding(14)
    }

    @ViewBuilder private var list: some View {
        SettingRow(title: "Idle sessions", caption: Format.idleCaption) {
            ChoiceBar(title: "Idle sessions", choices: IdleSessions.allCases, label: { $0.label }, selection: $settings.idleSessions)
        }
        // The panel's own two words for what has stopped: a session is idle, an agent is done.
        SettingRow(title: Format.keepTitle, caption: Format.keepCaption) {
            ChoiceBar(title: Format.keepTitle, choices: Settings.keepFinishedChoices, label: { "\($0)m" }, selection: $settings.keepFinishedMinutes)
        }
        SettingRow(title: "Plan limits", caption: Format.limitsCaption, note: limitsNote) {
            Switch(title: "Plan limits", isOn: $settings.planLimits)
        }
        SettingRow(title: "Token use", caption: Format.usageCaption) {
            Switch(title: "Token use", isOn: $settings.tokenUse)
        }
    }

    @ViewBuilder private var sounds: some View {
        SettingRow(title: "Sounds", caption: Format.soundsCaption) {
            Switch(title: "Sounds", isOn: $settings.sounds)
        }
        if settings.sounds {
            SettingRow(title: "When an agent needs you") {
                Switch(title: "Sound when an agent needs you", isOn: $settings.soundNeedsYou)
            }
            SettingRow(title: "When a session finishes", caption: Format.finishedCaption) {
                Switch(title: "Sound when a session finishes", isOn: $settings.soundFinished)
            }
            SettingRow(title: "Remind again", caption: Format.remindCaption) {
                ChoiceBar(title: "Remind again", choices: Settings.remindChoices, label: { $0 == 0 ? "Off" : "\($0)m" }, selection: $settings.remindMinutes)
            }
            SettingRow(title: "Quiet hours") {
                Switch(title: "Quiet hours", isOn: $settings.quietHours)
            }
            if settings.quietHours {
                SettingRow(title: "From") {
                    HourStepper(title: "Quiet hours from", hour: $settings.quietFrom)
                }
                SettingRow(title: "Until") {
                    HourStepper(title: "Quiet hours until", hour: $settings.quietUntil)
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        SettingRow(title: "Answer from the notch", caption: Format.answersCaption(on: settings.answers)) {
            Switch(title: "Answer from the notch", isOn: $settings.answers)
        }
        if settings.answers {
            // The person installs the plugin themselves: the app never writes into ~/.claude.
            VStack(alignment: .leading, spacing: 6) {
                let command = Format.installCommand(resources: Bundle.main.resourceURL ?? Bundle.main.bundleURL, replacing: answers.pluginLost)
                // What it does before how to put it in, and each in full: none of it may end in "…".
                Group {
                    Text(verbatim: Format.pluginWhat)
                    Text(verbatim: Format.installSteps.run).padding(.top, 2)
                }
                .foregroundStyle(.white.opacity(0.6)).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                // Whole, however long the app's path is: it is run in a terminal as it stands.
                commandRow(command, spoken: "Copy the install command")
                if answers.pluginLost {
                    // In full white, as a failure on this page is.
                    Text(verbatim: Format.pluginLostNote).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    Text(verbatim: Format.installSteps.restart)
                    Text(verbatim: Format.marketplaceNote)
                }
                .foregroundStyle(.white.opacity(0.6)).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                if let status = Format.answersStatus(answers.state, now: Date()) {
                    // A failure in full white, as every other one on this page.
                    Text(verbatim: status).foregroundStyle(.white.opacity(answers.state.isFailure ? 1 : 0.6)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // What was put in by hand comes out by hand, and the way out is there whether or not
        // the switch is on: switching off does not take the plugin out. Under the switch, after
        // the command that puts it in, and folded: it is rarely needed.
        Fold(title: Format.removePlugin) {
            commandRow(Format.uninstallCommand, spoken: "Copy the command that removes the plugin")
        }
        SettingRow(title: Format.crewTitle, caption: Format.crewWhat) { EmptyView() }
        let crewExe = Format.stablePath(Bundle.main.executableURL ?? Bundle.main.bundleURL)
        Fold(title: Format.crewSetup) {
            Text(verbatim: Format.crewSteps.run)
                .foregroundStyle(.white.opacity(0.6)).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            commandRow(Format.crewCommand(executable: crewExe, "install"), spoken: "Copy the command that puts the crew in the terminal")
            Text(verbatim: Format.crewSteps.restart)
                .foregroundStyle(.white.opacity(0.6)).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
        Fold(title: Format.removeCrew) {
            commandRow(Format.crewCommand(executable: crewExe, "uninstall"), spoken: "Copy the command that takes the crew out of the terminal")
            Text(verbatim: Format.removeCrewNote)
                .foregroundStyle(.white.opacity(0.6)).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
        SettingRow(title: "Go to the session's tab", caption: Format.tabCaption) {
            Switch(title: "Go to the session's tab", isOn: $settings.goToTab)
        }
        SettingRow(title: "Shortcut", caption: Format.shortcutCaption, note: settings.shortcut ? shortcutNote : nil) {
            Switch(title: "Keyboard shortcut", isOn: $settings.shortcut)
        }
        .id(ScrollTarget.shortcutID)
        if settings.shortcut {
            // More than one: another app can hold a chord already.
            SettingRow(title: "Shortcut keys") {
                ChoiceBar(title: "Shortcut keys", choices: ShortcutKey.allCases, label: { Format.shortcut($0) }, selection: $settings.shortcutKey)
            }
        }
    }

    /// 0.1 from Homebrew is still installed: the one command that takes it out, first on the
    /// page the panel's Fix it opens.
    @ViewBuilder private var oldCopy: some View {
        // In full white, as a failure on this page is.
        Text(verbatim: Format.oldCopyNote).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        commandRow(AppPlace.removeOldFormula, spoken: "Copy the command that takes our 0.1 out")
    }

    @ViewBuilder private var app: some View {
        SettingRow(title: "Open at login", note: loginError) {
            Switch(title: "Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
        }
        // Only in a release: a build to work on the app has nothing to update from.
        if updates.isAvailable {
            SettingRow(title: Format.updatesTitle, caption: Format.updatesCaption) {
                Switch(title: Format.updatesTitle, isOn: Binding(get: { updates.checksAutomatically }, set: { updates.checksAutomatically = $0 }))
            }
            Button { updates.checkNow() } label: {
                Text(verbatim: Format.checkNow)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .contentShape(Rectangle())
                    .hoverFill()
                    .padding(.horizontal, -6)
            }
            .buttonStyle(.plain)
        }
        // Which app this is and what it will not do, for someone it was handed to.
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: Format.about(name: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
                                        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String))
            // In full: a promise cut short is no promise.
            Text(verbatim: Format.readOnly(updates: updates.isAvailable)).foregroundStyle(.white.opacity(0.6)).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
        // The crew's tip jar. The browser opens it; the app itself stays offline.
        Button { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/morsechimwai")!) } label: {
            quietLabel("Sponsor the crew")
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens GitHub Sponsors in your browser")
        // A new issue with the version, macOS and Mac filled in. Also only the browser: the person
        // reads it all before they send it.
        Button {
            NSWorkspace.shared.open(Format.bugReport(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                macOS: ProcessInfo.processInfo.operatingSystemVersion, mac: Self.macModel))
        } label: {
            quietLabel("Report a bug")
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a new GitHub issue in your browser")
        // Last and quiet: the rarest action, kept away from anything clicked in passing.
        Button { NSApp.terminate(nil) } label: {
            quietLabel(Format.quit(appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String))
        }
        .buttonStyle(.plain)
    }

    /// A row-wide button in grey text that lights up under the pointer.
    private func quietLabel(_ title: String) -> some View {
        Text(verbatim: title)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contentShape(Rectangle())
            .hoverFill()
            .padding(.horizontal, -6)
    }

    /// The Mac's model, such as Mac15,6: tells which notch it has.
    private static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    /// Why the limits are missing, under their switch: the status row only has room to say that they are.
    private var limitsNote: String? {
        if case .unavailable(let reason) = limits.display { return Format.limitsReason(reason) }
        return nil
    }

    /// A command to run in a terminal, in full, with a button that copies it.
    private func commandRow(_ command: String, spoken: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: command).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 8)
            Button { copy(command) } label: {
                Text(verbatim: copied == command ? "Copied" : "Copy")
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.35)))
                    .contentShape(Rectangle())
                    .hoverFill()
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(Text(verbatim: spoken))
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = command
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == command { copied = nil } }
    }

    /// macOS owns this setting; the switch shows whatever the system ends up with.
    private func setOpenAtLogin(_ on: Bool) {
        var failure: Error?
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error
        }
        if on, failure == nil { settings.loginItemPath = Bundle.main.bundlePath }
        let status = SMAppService.mainApp.status
        loginError = LoginItem.message(wanted: on, status: status, error: failure, appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        openAtLogin = status == .enabled
    }
}

enum LoginItem {
    /// macOS keeps a login item by the app's path, and Homebrew gives each version a folder of
    /// its own and deletes the one before: after an upgrade the item names an app that is gone.
    /// Opened from a new place, the app registers again, from there.
    static func follow(_ settings: Settings, to path: String = Bundle.main.bundlePath) {
        guard SMAppService.mainApp.status == .enabled, settings.loginItemPath != path else { return }
        try? SMAppService.mainApp.unregister()
        if (try? SMAppService.mainApp.register()) != nil { settings.loginItemPath = path }
    }

    /// What to say under the switch after trying to set it, or nil when it simply worked.
    static func message(wanted: Bool, status: SMAppService.Status, error: Error?, appName: String? = nil) -> String? {
        if let error {
            return "Could not \(wanted ? "enable" : "disable"): \(error.localizedDescription)"
        }
        // Registered, but switched off by hand in System Settings: macOS will not run it until allowed.
        if wanted, status == .requiresApproval {
            return "Allow \(appName ?? "this app") in System Settings > General > Login Items"
        }
        return nil
    }
}

/// The way back to the list, in words, from whatever stands in its place or over it.
struct BackToAgents: View {
    var title = "Agents"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left").font(.system(size: 9, weight: .bold))
                Text(verbatim: title)
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
            .hoverFill()
            .padding(.leading, -6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Back to " + title.lowercased()))
    }
}

/// One line that unfolds what is rarely needed, so it does not push Quit off the page.
private struct Fold<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { open.toggle() } label: {
                HStack(spacing: 8) {
                    FoldMark(open: open)
                    Text(verbatim: title)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
                .contentShape(Rectangle())
                .hoverFill()
                .padding(.horizontal, -6)
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(verbatim: open ? "Shown" : "Hidden"))
            if open { content.padding(.leading, 17) }
        }
    }
}

/// The pages of the legend: on one page the list of keys ran off the foot of the panel.
enum LegendTab: String, CaseIterable {
    /// Who a mascot is, what its dot says, and the words on its row.
    case mascots
    /// The numbers and the mascot on the bar, with the panel shut.
    case bar
    case keys

    /// The word on its tab.
    var label: String { rawValue.capitalized }
}

/// What the creatures and the bar's numbers mean, drawn as the panel draws them.
struct Legend: View {
    /// The page shown. Kept by whoever shows the legend, so that its key can open it on the keys.
    @Binding var tab: LegendTab
    /// Puts the legend away, where it stands at the head of the list. Nil on the settings page,
    /// which has its own way back.
    var back: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // As on the settings page: the way back on the left, the pages on the right.
                if let back {
                    BackToAgents(action: back)
                    Spacer(minLength: 0)
                }
                PageTabs(title: Format.legendTitle, pages: LegendTab.allCases, label: { $0.label }, selection: $tab)
            }
            switch tab {
            case .mascots: mascots
            case .bar: bar
            case .keys: keys
            }
        }
    }

    @ViewBuilder private var mascots: some View {
        caption(Format.legendCaption)
        // Standing still: only who it is is the point here.
        HStack(spacing: 12) {
            item("session", kinds: Person.leads.indices.map { .lead(LeadLook(face: $0, hair: $0, shirt: $0)) })
            item("general-purpose", kinds: [.general])
            item("Explore", kinds: [.explore])
            item("Plan", kinds: [.plan])
        }
        // Any other type of agent is the general-purpose person in one of these shirts, picked by
        // its name, always the same one.
        item("other types, each in its own colour", kinds: Person.otherShirts.indices.map { .other(shirt: $0) })
        HStack(spacing: 12) {
            item("working", status: .working)
            item("quiet", status: .quiet, flag: .quiet)
            item("needs you", flag: .needsYou)
            item("idle or done", status: .done)
        }
        caption(Format.quietCaption)
        caption(Format.timeCaption)
    }

    @ViewBuilder private var bar: some View {
        // The bar's numbers, drawn as the bar draws them.
        HStack(spacing: 12) {
            mark("needs you") { BarBadge(count: 1) }
            mark("working") { Text(verbatim: "2").bold() }
            mark("quiet") { Text(verbatim: "2").foregroundStyle(.white.opacity(0.6)) }
            // A ring as an example, two thirds used: the real one is on the bar.
            mark("5h limit") { LimitRingView(ring: LimitRing(limit: PlanLimit(usedPercent: 65, resetsAt: nil), stale: false)).accessibilityHidden(true) }
        }
        caption(Format.barCaption)
        caption(Format.ringCaption)
        caption(Format.barMascotCaption)
        caption(Format.beatCaption)
        caption(Format.displayCaption)
    }

    @ViewBuilder private var keys: some View {
        // Keys in two columns: the key, then what it does. A list, not a sentence to read through.
        caption(Format.keysCaption)
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 3) {
            ForEach(Array(Format.keys.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 8) {
                    Text(verbatim: entry.key).frame(width: 52, alignment: .leading)
                    Text(verbatim: entry.does).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private func mark<Sample: View>(_ label: String, @ViewBuilder sample: () -> Sample) -> some View {
        HStack(spacing: 6) {
            sample()
            Text(verbatim: label).foregroundStyle(.white.opacity(0.8)).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(_ text: String, lines: Int = 3) -> some View {
        Text(verbatim: text).foregroundStyle(.white.opacity(0.6)).lineLimit(lines).fixedSize(horizontal: false, vertical: true)
    }

    private func item(_ label: String, kinds: [MascotKind] = [.general], status: AgentStatus = .needsYou, flag: MascotFlag? = nil) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                MascotView(status: status, kind: kind, size: 14, flag: flag)
            }
            Text(verbatim: label).foregroundStyle(.white.opacity(0.8)).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    var caption: String? = nil
    /// Something that needs the person's attention, in full white under the caption.
    var note: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: title)
                Spacer()
                control
            }
            // What is wrong comes first, in full white: under a caption of four lines it sat
            // below the edge of the page.
            if let note {
                Text(verbatim: note).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if let caption {
                // Room for the longest caption in full: a promise about the login must not end in "…".
                Text(verbatim: caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Plain SwiftUI buttons rather than system controls: the panel never becomes the key window,
/// and buttons are what is known to take clicks there.
private struct Switch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule().fill(isOn ? Color.white : Color.white.opacity(0.2))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    // Off, the knob is no brighter than the row's own words.
                    Circle().fill(isOn ? Color.black : Color.white.opacity(0.6)).frame(width: 16, height: 16).padding(2)
                }
                // A ring of fill around it: behind a switch that is on, a fill would not show.
                .padding(4)
                .contentShape(Rectangle())
                .hoverFill(radius: 14)
                .padding(-4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: isOn ? "On" : "Off"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// The pages of a view: words, the open one underlined. In the filled bar a setting's choices
/// sit in, the choice of idle sessions under the settings' pages read as a second row of pages.
struct PageTabs<Page: Hashable>: View {
    let title: String
    let pages: [Page]
    let label: (Page) -> String
    @Binding var selection: Page

    var body: some View {
        HStack(spacing: 2) {
            ForEach(pages, id: \.self) { page in
                Button { selection = page } label: {
                    Text(verbatim: label(page))
                        .foregroundStyle(page == selection ? Color.white : Color.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(page == selection ? Color.white : Color.clear).frame(height: 2).padding(.horizontal, 8)
                        }
                        .contentShape(Rectangle())
                        .hoverFill()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == selection ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: title))
    }
}

struct ChoiceBar<Value: Hashable>: View {
    let title: String
    let choices: [Value]
    let label: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices, id: \.self) { choice in
                Button { selection = choice } label: {
                    Text(verbatim: label(choice))
                        .foregroundStyle(choice == selection ? Color.black : Color.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(choice == selection ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .hoverFill(darkens: choice == selection)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choice == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: title))
    }
}

/// An hour of the day, moved one at a time and round the clock. Buttons, as every control
/// here: the panel never becomes the key window.
private struct HourStepper: View {
    let title: String
    @Binding var hour: Int

    var body: some View {
        HStack(spacing: 2) {
            step("minus", by: -1, spoken: "Earlier")
            Text(verbatim: Format.hour(hour)).monospacedDigit().frame(minWidth: 44)
            step("plus", by: 1, spoken: "Later")
        }
        .padding(2)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: Format.hour(hour)))
    }

    private func step(_ symbol: String, by amount: Int, spoken: String) -> some View {
        Button { hour = Sound.hour(hour, movedBy: amount) } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 22).contentShape(Rectangle()).hoverFill()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: spoken))
    }
}
