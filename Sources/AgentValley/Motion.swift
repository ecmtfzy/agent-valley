import SwiftUI

/// Every curve and distance in the panel's motion. Reduce Motion keeps the fades that carry
/// state and drops everything that travels or changes size over time.
struct Motion {
    let reduced: Bool

    /// The island growing out of the notch and snapping back into it. Leaving is quicker than
    /// arriving and does not bounce.
    func resize(opening: Bool) -> Animation? {
        if reduced { return nil }
        return opening ? .spring(response: 0.42, dampingFraction: 0.76) : .spring(response: 0.26, dampingFraction: 1)
    }

    /// Cards follow the island's edge down one after another. Capped so a long list never
    /// keeps anyone waiting.
    func revealDelay(index: Int) -> Double {
        reduced ? 0 : 0.07 + 0.035 * Double(min(index, 4))
    }

    func reveal(index: Int) -> Animation {
        reduced
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.34, dampingFraction: 0.86).delay(revealDelay(index: index))
    }

    var conceal: Animation { .easeOut(duration: 0.09) }

    /// Rows and cards joining, leaving, or changing height.
    var list: Animation { reduced ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.82) }

    /// Where a card starts from on its way in.
    var travel: CGFloat { reduced ? 0 : -12 }

    /// The mascot's jump when the cursor arrives.
    var hop: CGFloat { reduced ? 0 : -5 }

    /// How far the red count swells when someone starts to wait. It does so three times over a
    /// second and a half: once was seen only by someone already looking at it.
    var pulse: CGFloat { reduced ? 1 : 1.5 }

    /// How often the red count beats again while someone waits, or nil for never. Claude Code
    /// reports a wait some seconds after it begins, so a mark made once comes when nobody is
    /// looking; the working mascots move all the time, and what is stuck must not be the still one.
    var waitingBeat: TimeInterval? { reduced ? nil : 3 }

    /// How red the whole bar glows at the top of a beat while someone waits. The red count is
    /// 18 points across: however it moved, it was too small to catch an eye that was elsewhere.
    /// Under Reduce Motion nothing flashes: the red count stands for the wait by itself.
    var flash: Double { reduced ? 0 : 0.6 }

    /// Under Reduce Motion that moment is a fade in place of a change of size: the count dips
    /// to this and comes back.
    var pulseDim: Double { reduced ? 0.3 : 1 }

    /// The sizes the red count passes through as someone starts to wait: three swells, each back
    /// to rest. Under Reduce Motion it keeps its size.
    var arrivalSwells: [CGFloat] { reduced ? [1] : [pulse, 1, pulse, 1, pulse, 1] }

    /// Its brightness through the same moment. Under Reduce Motion one dip and back, once, in
    /// place of the swells.
    var arrivalDips: [Double] { reduced ? [pulseDim, 1] : [1] }

    /// How long that mark takes.
    var arrivalLasts: TimeInterval { 1.5 }

    /// Whether a beat may come this long after someone started to wait. Never on top of the mark
    /// of the arrival: the two swells at once made the count more than twice its size, taller
    /// than the bar. And never under Reduce Motion.
    func beats(sinceArrival seconds: TimeInterval) -> Bool {
        waitingBeat != nil && seconds >= arrivalLasts
    }

    var rowEntrance: AnyTransition {
        reduced ? .opacity : .opacity.combined(with: .offset(y: -8))
    }
}
