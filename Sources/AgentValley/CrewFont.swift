import CryptoKit
import Foundation

/// The three moments of a crew member that Claude Code's terminal shows.
enum CrewPose: Int, CaseIterable {
    case working, needsYou, done
}

/// The crew's faces as characters of a colour font, for Claude Code's status line and sub-agent
/// rows. Every face is one wide character of the unassigned end of Plane 3, so every terminal
/// gives it two cells. The cells come from `MascotView.pose`, the same ones the notch draws.
enum CrewFont {
    static let family = "AgentValley Crew"
    static let fileName = "AgentValleyCrew.ttf"
    static let firstScalar: UInt32 = 0x3F000

    /// The end of the block the font keeps to, and Ghostty's font line maps.
    static let lastScalar: UInt32 = 0x3F7FF

    struct Face {
        let scalar: UInt32
        let person: Person
        let pose: CrewPose
        /// At work with this in hand, as the notch draws it standing still.
        var holding: Activity?
    }

    private static let crew: [MascotKind] = [.general, .explore, .plan, .other(shirt: 0), .other(shirt: 1), .other(shirt: 2), .other(shirt: 3)]
    private static let leadCount = Person.leads.count * Person.leadHair.count * Person.leadShirts.count

    /// The crew first, three poses each, then every look a session's own agent can have, in
    /// the working pose only; then all of them at work with each thing in hand, crew first.
    /// The order is fixed: fonts already shipped refer to it, so new faces only ever go at the end.
    static let faces: [Face] = {
        var all = crew.flatMap { kind in CrewPose.allCases.map { Face(scalar: 0, person: kind.person, pose: $0) } }
        var leads: [Person] = []
        for face in 0..<Person.leads.count {
            for hair in 0..<Person.leadHair.count {
                for shirt in 0..<Person.leadShirts.count {
                    leads.append(MascotKind.lead(LeadLook(face: face, hair: hair, shirt: shirt)).person)
                }
            }
        }
        all += leads.map { Face(scalar: 0, person: $0, pose: .working) }
        all += (crew.map(\.person) + leads).flatMap { person in
            Activity.allCases.map { Face(scalar: 0, person: person, pose: .working, holding: $0) }
        }
        return all.enumerated().map { Face(scalar: firstScalar + UInt32($0.offset), person: $0.element.person, pose: $0.element.pose, holding: $0.element.holding) }
    }()

    /// The one character that draws `kind` in `pose`, holding what `holding` names while it works.
    /// A session's own agent has working faces only.
    static func character(_ kind: MascotKind, _ pose: CrewPose, holding: Activity? = nil) -> String {
        let place: Int
        switch kind {
        case .general: place = 0
        case .explore: place = 1
        case .plan: place = 2
        case .other(let shirt): place = 3 + shirt % Person.otherShirts.count
        case .lead(let look):
            place = crew.count + (look.face % Person.leads.count) * 42 + (look.hair % Person.leadHair.count) * 7 + look.shirt % Person.leadShirts.count
        }
        let index: Int
        if let holding, pose == .working {
            index = crew.count * 3 + leadCount + place * Activity.allCases.count + Activity.allCases.firstIndex(of: holding)!
        } else if place >= crew.count {
            index = crew.count * 3 + place - crew.count
        } else {
            index = place * 3 + pose.rawValue
        }
        return String(UnicodeScalar(firstScalar + UInt32(index))!)
    }

    /// Every face as text built by hand, not by `JSONSerialization`, so the bytes are the same on
    /// every Mac. `rects` are runs of one colour along a row, on a 12 by 12 grid, `x1` not included.
    static func facesJSON() -> Data {
        let faces = faces.map { face -> String in
            var cells: [[Character]]
            let opacity: Double
            switch face.pose {
            case .working: (cells, opacity) = (MascotView.pose(face.person, status: .working, callsOut: false, blink: false, wave: 0), 1)
            case .needsYou: (cells, opacity) = (MascotView.pose(face.person, status: .needsYou, callsOut: true, blink: false, wave: 0), 1)
            case .done: (cells, opacity) = (MascotView.pose(face.person, status: .done, callsOut: false, blink: false, wave: 0), 0.45)
            }
            if let holding = face.holding {
                cells = MascotView.hold(holding, cells, under: face.person.underEyes, tick: MascotView.stillTick)
            }
            var rects: [String] = []
            for (y, row) in cells.enumerated() {
                var x = 0
                while x < row.count {
                    guard let hex = face.person.hex(row[x]) else { x += 1; continue }
                    var end = x + 1
                    while end < row.count, face.person.hex(row[end]) == hex { end += 1 }
                    rects.append("[\(x),\(end),\(y),\"\(String(format: "%06X", hex))\"]")
                    x = end
                }
            }
            return "{\"codepoint\":\(face.scalar),\"opacity\":\(String(format: "%.2f", opacity)),\"rects\":[\(rects.joined(separator: ","))]}"
        }
        return Data("{\"family\":\"\(family)\",\"faces\":[\(faces.joined(separator: ","))]}".utf8)
    }

    /// Says which faces a font was built from, so a font that is behind the code can be told.
    static var facesHash: String {
        SHA256.hash(data: facesJSON()).map { String(format: "%02x", $0) }.joined()
    }

    static var uniqueName: String { "AgentValleyCrew-" + facesHash }
}
