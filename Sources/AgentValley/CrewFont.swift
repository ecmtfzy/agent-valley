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

    struct Face {
        let scalar: UInt32
        let person: Person
        let pose: CrewPose
    }

    /// The crew first, three poses each, then every look a session's own agent can have, in
    /// the working pose only. The order is fixed: fonts already shipped refer to it.
    static let faces: [Face] = {
        let crew: [MascotKind] = [.general, .explore, .plan, .other(shirt: 0), .other(shirt: 1), .other(shirt: 2), .other(shirt: 3)]
        var all = crew.flatMap { kind in CrewPose.allCases.map { (kind.person, $0) } }
        for face in 0..<Person.leads.count {
            for hair in 0..<Person.leadHair.count {
                for shirt in 0..<Person.leadShirts.count {
                    all.append((MascotKind.lead(LeadLook(face: face, hair: hair, shirt: shirt)).person, .working))
                }
            }
        }
        return all.enumerated().map { Face(scalar: firstScalar + UInt32($0.offset), person: $0.element.0, pose: $0.element.1) }
    }()

    /// The one character that draws `kind` in `pose`. A session's own agent has the working face only.
    static func character(_ kind: MascotKind, _ pose: CrewPose) -> String {
        let index: Int
        switch kind {
        case .general: index = pose.rawValue
        case .explore: index = 3 + pose.rawValue
        case .plan: index = 6 + pose.rawValue
        case .other(let shirt): index = 9 + (shirt % Person.otherShirts.count) * 3 + pose.rawValue
        case .lead(let look):
            let face = look.face % Person.leads.count, hair = look.hair % Person.leadHair.count
            index = 21 + face * 42 + hair * 7 + look.shirt % Person.leadShirts.count
        }
        return String(UnicodeScalar(firstScalar + UInt32(index))!)
    }

    /// Every face as text built by hand, not by `JSONSerialization`, so the bytes are the same on
    /// every Mac. `rects` are runs of one colour along a row, on a 12 by 12 grid, `x1` not included.
    static func facesJSON() -> Data {
        let faces = faces.map { face -> String in
            let cells: [[Character]]
            let opacity: Double
            switch face.pose {
            case .working: (cells, opacity) = (MascotView.pose(face.person, status: .working, callsOut: false, blink: false, wave: 0), 1)
            case .needsYou: (cells, opacity) = (MascotView.pose(face.person, status: .needsYou, callsOut: true, blink: false, wave: 0), 1)
            case .done: (cells, opacity) = (MascotView.pose(face.person, status: .done, callsOut: false, blink: false, wave: 0), 0.45)
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
