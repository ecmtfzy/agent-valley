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
        for (index, frame) in Mug.frames.enumerated() {
            try svg(frame.map(Array.init), colour: Mug.hex, opacity: 1)
                .write(toFile: "\(out)/mug-\(index).svg", atomically: true, encoding: .utf8)
        }
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
