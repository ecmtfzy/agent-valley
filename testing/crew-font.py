# Builds AgentValleyCrew.ttf from the faces JSON that CrewFont.facesJSON() writes. Everything
# drawn comes from that file: this script holds no people, poses or colours of its own.
# Each face is ONE wide character from the unassigned end of Plane 3: every terminal and Claude Code
# give it two cells (East Asian Wide), Chrome-based terminals look it up in any installed font
# (they never do for private use), and Ghostty fits a colour glyph to its cells in one piece.
# Usage: crew-font.py faces.json out.ttf
import hashlib, json, sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.S_V_G_ import SVGDocument

PX = 100            # font units per picture pixel
TOP = 1000          # the face's top edge; bottom edge is TOP - 12 * PX
WIDE = 1440         # two monospace cells of 0.6 em
LEFT = (WIDE - 12 * PX) // 2

raw = open(sys.argv[1], "rb").read()
data = json.loads(raw)
FAMILY = data["family"]
PS = FAMILY.replace(" ", "")

palette, index = [], {}
def pal(hexrgb, alpha):
    rgb = int(hexrgb, 16)
    if (rgb, alpha) not in index:
        index[(rgb, alpha)] = len(palette)
        palette.append((((rgb >> 16) & 255) / 255, ((rgb >> 8) & 255) / 255, (rgb & 255) / 255, alpha))
    return index[(rgb, alpha)]

def outline(rects, frame=False):
    pen = TTGlyphPen(None)
    if frame:  # zero-area marks: bounds are the whole two cells, which Ghostty fits to the cells
        for x, y in ((0, TOP - 12 * PX), (WIDE, TOP)):
            pen.moveTo((x, y)); pen.lineTo((x, y)); pen.closePath()
    for x0, x1, y, _ in rects:
        y0 = TOP - (y + 1) * PX
        pen.moveTo((x0, y0)); pen.lineTo((x0, y0 + PX)); pen.lineTo((x1, y0 + PX)); pen.lineTo((x1, y0)); pen.closePath()
    return pen.glyph()

order, glyphs, cmap, colr, svg_src = [".notdef"], {".notdef": TTGlyphPen(None).glyph()}, {}, {}, {}
for face in data["faces"]:
    key, alpha = f"u{face['codepoint']:X}", face["opacity"]
    # Runs of one colour in a row are one rectangle, so no seam shows between same-coloured
    # pixels when the size isn't whole pixels. Units are font units from here on.
    rects = [(LEFT + x0 * PX, LEFT + x1 * PX, y, c) for x0, x1, y, c in face["rects"]]
    order.append(key); glyphs[key] = outline(rects, frame=True); cmap[face["codepoint"]] = key
    layers = []
    for i, c in enumerate(dict.fromkeys(r[3] for r in rects)):
        layer = f"{key}.{i}"
        order.append(layer); glyphs[layer] = outline([r for r in rects if r[3] == c])
        layers.append((layer, pal(c, alpha)))
    colr[key] = layers
    svg_src[key] = (rects, alpha)

fb = FontBuilder(1200, isTTF=True)
fb.setupGlyphOrder(order)
fb.setupCharacterMap(cmap)
fb.setupGlyf(glyphs)
glyf = fb.font["glyf"]
def lsb(name):  # a glyph's left side bearing must be its own left edge, or each layer slides
    g = glyf[name]; g.recalcBounds(glyf)
    return getattr(g, "xMin", 0) if g.numberOfContours else 0
fb.setupHorizontalMetrics({g: (WIDE, lsb(g)) for g in order})
fb.setupHorizontalHeader(ascent=1000, descent=-200)
fb.setupNameTable({"familyName": FAMILY, "styleName": "Regular",
                   "uniqueFontIdentifier": f"AgentValleyCrew-{hashlib.sha256(raw).hexdigest()}",
                   "fullName": f"{FAMILY} Regular", "psName": f"{PS}-Regular", "version": "Version 1.0"})
fb.setupOS2(sTypoAscender=1000, sTypoDescender=-200, usWinAscent=1000, usWinDescent=200, sxHeight=660, sCapHeight=876)
fb.setupPost()
fb.setupCOLR(colr, version=0)
fb.setupCPAL([palette])

# OpenType-SVG copy of each face: Ghostty draws colour only from sbix or SVG, not COLR
docs = []
for name, (rects, a) in svg_src.items():
    gid = order.index(name)
    body = "".join(f'<rect x="{x0}" y="{-(TOP - y * PX)}" width="{x1 - x0}" height="{PX}" fill="#{c}" fill-opacity="{a}"/>'
                   for x0, x1, y, c in rects)
    frame = f'<rect x="0" y="{-TOP}" width="{WIDE}" height="{12 * PX}" fill="#000" fill-opacity="0"/>'
    docs.append(SVGDocument(f'<svg xmlns="http://www.w3.org/2000/svg"><g id="glyph{gid}">{frame}{body}</g></svg>', gid, gid, False))
svg = newTable("SVG "); svg.docList = sorted(docs, key=lambda d: d.startGlyphID)
fb.font["SVG "] = svg

fb.save(sys.argv[2])
print(sys.argv[2], len(data["faces"]), "faces", len(order), "glyphs", len(palette), "colours")
