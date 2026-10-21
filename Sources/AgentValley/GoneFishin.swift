import AppKit
import SwiftUI

/// Hung over the list while a plan limit has run out: the crew's sign on its rope, saying when
/// they are back, and beside it where they went. A few hours out fishing, or days away.
struct GoneFishin: View {
    let out: RunOut
    let now: Date

    var body: some View {
        let art = SignArt.of(weekly: out.weekly)
        let back = Format.backAt(out.resetsAt, now: now)
        HStack(spacing: 16) {
            ZStack(alignment: .top) {
                if let picture = art.picture {
                    Image(nsImage: picture).resizable().frame(width: art.size.width, height: art.size.height)
                }
                // The words painted on the board's middle, in the crew's own pixels.
                VStack(spacing: 5) {
                    PixelText(text: Format.fishingSign(weekly: out.weekly), pixel: 2.5, bold: true, paint: art.paint, shadow: art.shadow)
                    PixelText(text: back, pixel: 1.5, bold: false, paint: art.paint, shadow: art.shadow)
                }
                .frame(width: art.size.width)
                .frame(height: art.boardMiddle * 2)
            }
            .frame(width: art.size.width, height: art.size.height, alignment: .top)
            Text(verbatim: Format.fishingLine(weekly: out.weekly))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(Text(verbatim: "\(Format.fishingSign(weekly: out.weekly)). \(back). \(Format.fishingLine(weekly: out.weekly))"))
    }
}

/// A sign's picture and where its words go. The pictures are drawn boards with nothing on them,
/// in `signs/` and copied into the app by build-app.sh.
struct SignArt {
    let file: String
    /// As drawn in the panel: the picture is twice this, for a Retina screen.
    let size: CGSize
    /// How far down the picture the board's middle is: the rope and nail sit above it.
    let boardMiddle: CGFloat
    let paint: Color
    let shadow: Color

    /// Where the pictures are. The pictures of the panel drawn in tests point it at `signs/`.
    static var folder = Bundle.main.resourceURL ?? Bundle.main.bundleURL

    static let fishing = SignArt(file: "sign-fishing.png", size: CGSize(width: 270, height: 117), boardMiddle: 80,
                                 paint: rgb(0xF2EAD8), shadow: rgb(0x3E2410))
    /// Cream letters were lost on the light sea blue: these are painted navy.
    static let vacation = SignArt(file: "sign-vacation.png", size: CGSize(width: 270, height: 107.5), boardMiddle: 71.7,
                                  paint: rgb(0x1A3345), shadow: rgb(0x9CD8D6))

    static func of(weekly: Bool) -> SignArt { weekly ? vacation : fishing }

    var picture: NSImage? { NSImage(contentsOf: Self.folder.appendingPathComponent(file)) }
}

/// Words in a 5×7 pixel font, as a sign painter with square pixels would letter them, with a
/// shadow half a pixel down and right.
struct PixelText: View {
    let text: String
    /// The size of one of the font's pixels.
    let pixel: CGFloat
    let bold: Bool
    let paint: Color
    let shadow: Color
    @Environment(\.displayScale) private var scale

    var body: some View {
        let (cells, width) = PixelFont.cells(text, bold: bold)
        let lift = pixel / 2
        Canvas { graphics, _ in
            let snap = { (value: CGFloat) in (value * scale).rounded() / scale }
            for (colour, offset) in [(shadow, lift), (paint, 0)] {
                var path = Path()
                for cell in cells {
                    let left = snap(CGFloat(cell.x) * pixel + offset), top = snap(CGFloat(cell.y) * pixel + offset)
                    path.addRect(CGRect(x: left, y: top, width: snap(CGFloat(cell.x + 1) * pixel + offset) - left,
                                        height: snap(CGFloat(cell.y + 1) * pixel + offset) - top))
                }
                graphics.fill(path, with: .color(colour))
            }
        }
        .frame(width: CGFloat(width) * pixel + lift, height: 7 * pixel + lift)
        .accessibilityHidden(true)
    }
}

/// A 5×7 pixel font for the signs: capitals, digits, the colon and the apostrophe. Anything
/// else is left out.
enum PixelFont {
    static let glyphs: [Character: [String]] = [
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["111", "010", "010", "010", "010", "010", "111"],
        "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "10001", "01010", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["010", "110", "010", "010", "010", "010", "111"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["0", "1", "1", "0", "1", "1", "0"],
        "'": ["11", "01", "10", "00", "00", "00", "00"],
        " ": ["000", "000", "000", "000", "000", "000", "000"],
    ]

    /// The cells to fill for `text` in capitals, a pixel's gap between letters, and how many
    /// pixels wide it all is. Bold doubles every stroke one pixel to the right.
    static func cells(_ text: String, bold: Bool) -> (cells: [(x: Int, y: Int)], width: Int) {
        var cells: [(x: Int, y: Int)] = []
        var x = 0
        for letter in text.uppercased().replacingOccurrences(of: "\u{2019}", with: "'") {
            guard let rows = glyphs[letter] else { continue }
            for (y, row) in rows.enumerated() {
                for (column, bit) in row.enumerated() where bit == "1" {
                    cells.append((x + column, y))
                    if bold { cells.append((x + column + 1, y)) }
                }
            }
            x += rows[0].count + 1 + (bold ? 1 : 0)
        }
        return (cells, max(0, x - 1))
    }

    /// Whether every letter of `text` is in the font.
    static func covers(_ text: String) -> Bool {
        text.uppercased().replacingOccurrences(of: "\u{2019}", with: "'").allSatisfy { glyphs[$0] != nil }
    }
}
