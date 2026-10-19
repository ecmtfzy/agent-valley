import XCTest
@testable import AgentValley

/// Writes every person, in each pose, and the mug as SVG files for the website, from the same
/// cells and colours the panel draws. Not a test of anything: it is skipped unless
/// `testing/site.sh mascots` runs it.
final class SiteMascotsTests: XCTestCase {
    func testWriteTheMascotsForTheSite() throws {
        guard let out = ProcessInfo.processInfo.environment["SITE_MASCOTS_OUT"] else {
            throw XCTSkip("Run by testing/site.sh mascots.")
        }
        let people: [(String, Person)] = [("guru", .guru), ("walrus", .walrus), ("engineer", .engineer),
                                          ("pearls", .pearls), ("beatnik", .beatnik), ("afro", .afro), ("coder", .coder)]
        for (name, person) in people {
            let poses: [(String, AgentStatus, Bool, Bool, Int)] = [
                ("working", .working, false, false, 0),
                ("blink", .working, false, true, 0),
                ("wave0", .needsYou, true, false, 0),
                ("wave1", .needsYou, true, false, 1),
                ("quiet", .quiet, false, false, 0),
                ("done", .done, false, false, 0),
            ]
            for (pose, status, callsOut, blink, wave) in poses {
                let cells = MascotView.pose(person, status: status, callsOut: callsOut, blink: blink, wave: wave)
                try svg(cells, colour: person.hex, opacity: MascotView.fade(status))
                    .write(toFile: "\(out)/\(name)-\(pose).svg", atomically: true, encoding: .utf8)
            }
        }
        // At work with a thing in hand: one still, as the terminal's font draws it, and a strip of
        // the frames the notch steps through every 0.4 s, from that still on, one loop long.
        for (name, person) in people {
            for activity in Activity.allCases {
                let still = MascotView.hold(activity, MascotView.pose(person, status: .working, callsOut: false, blink: false, wave: 0),
                                            under: person.underEyes, tick: MascotView.stillTick)
                try svg(still, colour: person.hex, opacity: 1)
                    .write(toFile: "\(out)/\(name)-\(activity).svg", atomically: true, encoding: .utf8)
                let frames = (0..<Self.loop(activity)).map { index in
                    let tick = MascotView.stillTick + index
                    let posed = MascotView.pose(person, status: .working, callsOut: false, blink: tick % 8 == 0, wave: 0)
                    return MascotView.hold(activity, posed, under: person.underEyes, tick: tick)
                }
                try strip(frames, colour: person.hex)
                    .write(toFile: "\(out)/\(name)-\(activity)-run.svg", atomically: true, encoding: .utf8)
            }
        }
        for (index, frame) in Mug.frames.enumerated() {
            try svg(frame.map(Array.init), colour: Mug.hex, opacity: 1)
                .write(toFile: "\(out)/mug-\(index).svg", atomically: true, encoding: .utf8)
        }
    }

    /// Ticks until a thing in hand comes round again, blinks included (every 8 ticks). The site's
    /// CSS reads the count from the strip's width.
    static func loop(_ activity: Activity) -> Int { activity == .thinking ? 24 : 8 }

    func testEveryThingInHandComesRoundInItsLoop() {
        for activity in Activity.allCases {
            let n = Self.loop(activity)
            for tick in 0..<n {
                let a = MascotView.hold(activity, MascotView.pose(.guru, status: .working, callsOut: false, blink: tick % 8 == 0, wave: 0), under: Person.guru.underEyes, tick: tick)
                let b = MascotView.hold(activity, MascotView.pose(.guru, status: .working, callsOut: false, blink: (tick + n) % 8 == 0, wave: 0), under: Person.guru.underEyes, tick: tick + n)
                XCTAssertEqual(a, b, "\(activity) at \(tick)")
            }
        }
    }

    /// Frames side by side, 13 apart: an empty column after each keeps a neighbour's edge from
    /// bleeding into the frame shown. One path per colour: runs as `M x y h w v1 h-w z`.
    private func strip(_ frames: [[[Character]]], colour: (Character) -> UInt32?) -> String {
        var runs: [UInt32: String] = [:], order: [UInt32] = []
        for (index, cells) in frames.enumerated() {
            for (y, row) in cells.enumerated() {
                var x = 0
                while x < row.count {
                    guard let hex = colour(row[x]) else { x += 1; continue }
                    var end = x + 1
                    while end < row.count, colour(row[end]) == hex { end += 1 }
                    if runs[hex] == nil { order.append(hex) }
                    runs[hex, default: ""] += "M\(index * 13 + x) \(y)h\(end - x)v1h-\(end - x)z"
                    x = end
                }
            }
        }
        let paths = order.map { ##"<path fill="#\##(String(format: "%06X", $0))" d="\##(runs[$0]!)"/>"## }.joined()
        return #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \#(frames.count * 13) 12" shape-rendering="crispEdges">\#(paths)</svg>"# + "\n"
    }

    /// Cells as squares of a 12 by 12 view box, each run of one colour along a row one rectangle.
    private func svg(_ cells: [[Character]], colour: (Character) -> UInt32?, opacity: Double) -> String {
        var rects = ""
        for (y, row) in cells.enumerated() {
            var x = 0
            while x < row.count {
                guard let hex = colour(row[x]) else { x += 1; continue }
                var end = x + 1
                while end < row.count, colour(row[end]) == hex { end += 1 }
                // Two #s: `fill="#` would end a string that has one.
                rects += ##"<rect x="\##(x)" y="\##(y)" width="\##(end - x)" height="1" fill="#\##(String(format: "%06X", hex))"/>"##
                x = end
            }
        }
        let fade = opacity < 1 ? #" opacity="\#(opacity)""# : ""
        return #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 12 12" shape-rendering="crispEdges"\#(fade)>\#(rects)</svg>"# + "\n"
    }
}
