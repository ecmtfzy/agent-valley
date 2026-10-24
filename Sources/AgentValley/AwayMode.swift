import Foundation

/// When the owner is away from the Mac. Pure rules: the caller feeds in events and reads `on`.
struct AwayMode: Equatable {
    enum Trigger: Equatable {
        case screenLocked, panelButton, phoneButton, phoneMessage
    }

    /// After the panel's own button turns Away on, touches in this window do not turn it off.
    static let panelGrace: TimeInterval = 10

    private(set) var on = false
    private var since: Date?
    private var graceUntil: Date?
    /// The screen is locked, so input does not count as someone back at work.
    private var locked = false

    mutating func turnOn(_ trigger: Trigger, at: Date) {
        if !on {
            on = true
            since = at
        }
        if trigger == .panelButton { graceUntil = at.addingTimeInterval(Self.panelGrace) }
        if trigger == .screenLocked { locked = true }
    }

    mutating func turnOff() {
        on = false
        since = nil
        graceUntil = nil
        locked = false
    }

    mutating func screenUnlocked() {
        turnOff()
    }

    /// Input on the Mac after Away began turns it off, unless the screen is locked.
    mutating func noteLastInput(at: Date) {
        guard on, !locked, let start = graceUntil ?? since, at > start else { return }
        turnOff()
    }
}
