#!/bin/bash
# The website in site/, a Next.js app built to plain files in site/out: makes its pictures,
# checks it and serves it on this Mac. Files served as they are live in site/public.
#
#   testing/site.sh mascots   Writes every person and the mug as SVG to site/public/mascots, from
#                             the app's own cells and colours (SiteMascotsTests).
#   testing/site.sh og        Builds the site and saves the top of the page at 1200×630 as
#                             site/public/og.png, the picture a link to the site shows where it is shared.
#   testing/site.sh icon      Writes AppIcon.icns, the app's icon, from site/public/mark.svg.
#   testing/site.sh webicons  Writes site/public/favicon.ico and site/public/apple-touch-icon.png
#                             from site/public/mark.svg.
#   testing/site.sh social    Writes docs/social-preview.png at 1280×640, the picture GitHub shows
#                             for a link to the repo: the crew, the name and the line under it.
#                             It goes up by hand, in the repo's Settings, under Social preview.
#   testing/site.sh logo      Writes docs/logo.svg and docs/logo-dark.svg, the full logo for the
#                             README: the crew of mark.svg beside the name of logo.svg, as the
#                             footer lays them out. The dark copy has light letters for GitHub's dark theme.
#   testing/site.sh photo     Writes docs/crew-photo.webp, the crew photo framed as the site shows it,
#                             for the README.
#   testing/site.sh rows      Builds the site and writes docs/row-notes.png, the enlarged row with its
#                             notes in pen as the site draws it, for the README.
#   testing/site.sh report    Draws the report motion from the app: the History page and the two
#                             PDFs of a made-up September (ReportMotionAssetsTests), their totals
#                             in site/motion; then, with Remotion, the first page's head that the
#                             site shows, on nothing (site/public/report-sheet.webp), and docs/report-motion.gif
#                             for the README. Remotion fetches its Chrome on its first render.
#   testing/site.sh needs-you Draws the needs-you motion's pictures from the app: the panel shut
#                             while three made-up sessions work, shut with the red 1, open on the
#                             request and open once it is allowed (NeedsYouMotionAssetsTests), as
#                             WebP in site/public/needs-you; then, with Remotion, the still the
#                             site shows where nothing moves, and docs/needs-you.gif for the README.
#   testing/site.sh crew      Builds the site and, with Remotion, draws the crew at work: the stills
#                             the site shows where nothing moves, wide and tall (site/public/crew),
#                             and docs/crew.gif on the page's cream for the README.
#   testing/site.sh check     Installs, tests and builds the site; every line of the spec's copy is
#                             on the page, every file it points to is there, nothing is loaded
#                             from another site, and the browser tests pass.
#   testing/site.sh serve     Serves the built site, site/out, at http://localhost:8765.
set -euo pipefail
cd "$(dirname "$0")/.."

# Serves the built site on a port. Python's file server queues only 5 connections by default;
# a browser asks for more at once and the rest are reset, so some pictures never arrive.
serve_out() {
    python3 -c "import functools,http.server as h; h.ThreadingHTTPServer.request_queue_size=128; h.test(HandlerClass=functools.partial(h.SimpleHTTPRequestHandler,directory='site/out'),ServerClass=h.ThreadingHTTPServer,port=$1,bind='127.0.0.1')"
}

case "${1:-}" in
mascots)
    mkdir -p site/public/mascots
    SITE_MASCOTS_OUT="$PWD/site/public/mascots" swift test --filter SiteMascotsTests
    ls site/public/mascots | wc -l
    ;;
og)
    npm --prefix site run build >/dev/null
    serve_out 8766 >/dev/null 2>&1 &
    server=$!
    disown "$server"
    profile=$(mktemp -d)
    trap 'kill $server; rm -rf "$profile"' EXIT
    sleep 1
    # A profile of its own, so the person's open Chrome is not the one asked.
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$profile" \
        --hide-scrollbars --force-prefers-reduced-motion --virtual-time-budget=3000 \
        --window-size=1200,630 --screenshot="$PWD/site/public/og.png" "http://127.0.0.1:8766/" 2>/dev/null
    sips -g pixelWidth -g pixelHeight site/public/og.png | tail -2
    ;;
social)
    # Every mark and logo pixel lands on whole pixels: the crew at 14 to one, the name at 8.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    cat > "$work/social.html" <<HTML
<!doctype html><style>
@font-face{font-family:"Plex Mono";src:url(file://$PWD/testing/fonts/IBMPlexMono-Regular.woff2)}
html,body{margin:0;height:100%;background:#f1e8d4}
body{display:flex;flex-direction:column;align-items:center;justify-content:center}
.mark svg{display:block;width:224px;height:182px}
.logo svg{display:block;width:704px;height:96px;margin-top:56px}
p{margin:40px 0 0;font:30px "Plex Mono";color:#4d4439}
</style>
<div class="mark">$(cat site/public/mark.svg)</div><div class="logo">$(cat site/public/logo.svg)</div>
<p>A small valley of programmers in your notch.</p>
HTML
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$work/profile" \
        --hide-scrollbars --allow-file-access-from-files --virtual-time-budget=2000 --window-size=1280,640 \
        --screenshot="$PWD/docs/social-preview.png" "file://$work/social.html" 2>/dev/null
    sips -g pixelWidth -g pixelHeight docs/social-preview.png | tail -2
    ;;
photo)
    # The crew photo as the site's credits show it, print, date stamp and caption, on nothing,
    # for the README, where no CSS can frame it: docs/crew-photo.webp at twice its size.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    cat > "$work/photo.html" <<HTML
<!doctype html><style>
@font-face{font-family:"Plex Mono";src:url(file://$PWD/testing/fonts/IBMPlexMono-Regular.woff2)}
@font-face{font-family:"Plex Mono";font-weight:600;src:url(file://$PWD/testing/fonts/IBMPlexMono-SemiBold.woff2)}
html,body{margin:0;background:transparent}
.photo{position:absolute;left:40px;top:30px;width:532px;padding:14px 14px 18px;border-radius:3px;background:#fbf7ee;color:#2a2118;transform:rotate(-2.5deg);box-shadow:0 22px 40px -16px rgba(0,0,0,.35),0 1px 3px rgba(0,0,0,.2)}
.snap{position:relative;aspect-ratio:4/3;overflow:hidden;background:#6f7477;filter:sepia(.18) saturate(.92)}
.snap img{display:block;width:100%;height:100%;object-fit:cover}
.snap::after{content:"";position:absolute;inset:0;background:radial-gradient(ellipse at center,transparent 55%,rgba(30,15,5,.5))}
.stamp{position:absolute;z-index:1;right:5%;bottom:4%;color:#ff8a1f;font:600 .95rem "Plex Mono";letter-spacing:.08em;opacity:.9}
p{display:grid;gap:2px;margin:14px 0 0;padding:0 4px;font:400 .9375rem/1.5 "Plex Mono"}
b{font-weight:600}
</style>
<div class="photo"><div class="snap"><img src="file://$PWD/site/public/crew-photo.webp"><span class="stamp">'69 7 20</span></div>
<p><b>The AgentValley crew</b><span>Go take a break.</span><span>We'll call you when we need you.</span></p></div>
HTML
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$work/profile" \
        --hide-scrollbars --allow-file-access-from-files --default-background-color=00000000 \
        --force-device-scale-factor=2 --virtual-time-budget=2000 --window-size=640,580 \
        --screenshot="$work/photo.png" "file://$work/photo.html" 2>/dev/null
    python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2], quality=86, method=6)' \
        "$work/photo.png" docs/crew-photo.webp
    ls -l docs/crew-photo.webp
    ;;
rows)
    # At twice its size, on the page's cream with round corners: it reads on GitHub's dark theme too.
    npm --prefix site run build >/dev/null
    serve_out 8766 >/dev/null 2>&1 &
    server=$!
    disown "$server"
    work=$(mktemp -d)
    trap 'kill $server; rm -rf "$work"' EXIT
    sleep 1
    (cd site && OUT="$work/rows.png" node --input-type=module - <<'JS'
import { chromium } from '@playwright/test';
const browser = await chromium.launch({ channel: 'chrome' });
// Reduced motion: the arrows stand drawn from the start.
const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2, reducedMotion: 'reduce' });
await page.goto('http://127.0.0.1:8766/');
const figure = page.locator('figure.notes');
await figure.scrollIntoViewIfNeeded();
await page.evaluate(() => document.fonts.ready);
const box = await figure.boundingBox();
// As much cream beside the black box as above and below it.
await page.screenshot({ path: process.env.OUT, clip: { x: box.x - 32, y: box.y, width: box.width + 64, height: box.height } });
await browser.close();
JS
    )
    python3 -I - "$work/rows.png" docs/row-notes.png <<'PY'
import sys
from PIL import Image, ImageDraw
picture = Image.open(sys.argv[1]).convert('RGBA')
corners = Image.new('L', picture.size, 0)
ImageDraw.Draw(corners).rounded_rectangle((0, 0, *picture.size), radius=36, fill=255)
picture.putalpha(corners)
picture.save(sys.argv[2], optimize=True)
PY
    ls -l docs/row-notes.png
    sips -g pixelWidth -g pixelHeight docs/row-notes.png | tail -2
    ;;
report)
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    REPORT_MOTION_OUT="$work" swift test --filter ReportMotionAssetsTests >/dev/null
    for n in all shop-web; do sips -s format png -Z 2400 "$work/report-$n.pdf" --out "$work/report-$n.png" >/dev/null; done
    # What Remotion reads: the page cut to the panel; each PDF page 1300 wide, enough for the
    # camera's 2.35 times; the font. Kept out of site/public, which serves only what the site shows.
    mkdir -p "$work/public"
    python3 -I - "$work" "$work/public" <<'PY'
import sys
from PIL import Image
work, out = sys.argv[1], sys.argv[2]
for n in ('all', 'shop-web'):
    page = Image.open(f'{work}/history-{n}.png').convert('RGBA')
    page.crop(page.getbbox()).save(f'{out}/history-{n}.webp', quality=86, method=6)
    sheet = Image.open(f'{work}/report-{n}.png').convert('RGB')
    sheet.resize((1300, round(1300 * sheet.height / sheet.width)), Image.LANCZOS).save(f'{out}/report-{n}.webp', quality=86, method=6)
PY
    cp "$work/totals.json" site/motion/report-totals.json
    cp site/node_modules/geist/dist/fonts/geist-mono/GeistMono-Bold.woff2 "$work/public/"
    # The camera held on the first page's head (BEATS.zoomA), on nothing, cut to the page and its shadow.
    (cd site && npx remotion still motion/index.tsx ReportMotion "$work/still.png" --frame=74 --scale=1.25 \
        --props='{"loop":false,"bare":true}' --public-dir="$work/public" --log=error)
    python3 -I -c 'import sys; from PIL import Image; i = Image.open(sys.argv[1]).convert("RGBA"); i.crop(i.getchannel("A").getbbox()).save(sys.argv[2], quality=86, alpha_quality=90, method=6)' \
        "$work/still.png" site/public/report-sheet.webp
    (cd site && npx remotion render motion/index.tsx ReportMotion ../docs/report-motion.gif --codec=gif --every-nth-frame=2 --scale=0.6 \
        --props='{"loop":true}' --public-dir="$work/public" --log=error --overwrite)
    ls -l site/public/report-sheet.webp site/motion/report-totals.json docs/report-motion.gif
    sips -g pixelWidth -g pixelHeight site/public/report-sheet.webp docs/report-motion.gif | grep pixel
    if [ "$(stat -f %z docs/report-motion.gif)" -gt 5242880 ]; then
        echo "docs/report-motion.gif is over 5 MB: lower its --scale." >&2
        exit 1
    fi
    ;;
needs-you)
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    NEEDS_YOU_MOTION_OUT="$work" swift test --filter NeedsYouMotionAssetsTests >/dev/null
    # All four cut by one box, the open panel's, so they lie over one another in the motion.
    mkdir -p site/public/needs-you "$work/public"
    python3 -I - "$work" site/public/needs-you <<'PY'
import sys
from PIL import Image
work, out = sys.argv[1], sys.argv[2]
names = ('shut-working', 'shut-asking', 'open-asking', 'open-allowed')
pictures = {n: Image.open(f'{work}/{n}.png').convert('RGBA') for n in names}
left = pictures['open-asking'].getbbox()[0]
box = (left, 0, left + 1088, 840)
# Where the motion (site/motion/needs-you-motion.tsx: PANEL, ISLAND, HEIGHT) expects the app's
# shapes, in the cut pictures' pixels. When the app draws them elsewhere, change both.
expected = {'open-asking': (0, 0, 1088, 836), 'open-allowed': (0, 0, 1088, 742), 'shut-working': (244, 0, 844, 76), 'shut-asking': (244, 0, 844, 76)}
for n, want in expected.items():
    got = pictures[n].crop(box).getbbox()
    if got != want:
        sys.exit(f'{n} is drawn at {got}, the motion expects {want}: change site/motion/needs-you-motion.tsx with it.')
for n, picture in pictures.items():
    picture.crop(box).save(f'{out}/{n}.webp', quality=88, method=6)
PY
    # The entry loads the report's font for every composition.
    cp site/public/needs-you/shut-*.webp site/public/needs-you/open-*.webp site/node_modules/geist/dist/fonts/geist-mono/GeistMono-Bold.woff2 "$work/public/"
    mkdir -p "$work/public/mascots" && cp site/public/mascots/*.svg "$work/public/mascots/"
    # The terminal waiting, the red 1 and the pointer on the notch (BEATS.pointIn's end).
    (cd site && npx remotion still motion/index.tsx NeedsYouMotion "$work/still.png" --frame=58 --scale=1.25 \
        --props='{"base":""}' --public-dir="$work/public" --log=error)
    python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).convert("RGB").save(sys.argv[2], quality=86, method=6)' \
        "$work/still.png" site/public/needs-you/still.webp
    (cd site && npx remotion render motion/index.tsx NeedsYouMotion ../docs/needs-you.gif --codec=gif --every-nth-frame=2 --scale=0.5 \
        --props='{"base":""}' --public-dir="$work/public" --log=error --overwrite)
    ls -l site/public/needs-you docs/needs-you.gif
    if [ "$(stat -f %z docs/needs-you.gif)" -gt 5242880 ]; then
        echo "docs/needs-you.gif is over 5 MB: lower its --scale." >&2
        exit 1
    fi
    ;;
crew)
    # The crew at work (site/motion/crew-motion.tsx) in the page's pen, Caveat: the build has the copy
    # next/font keeps, the latin one.
    npm --prefix site run build >/dev/null
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    mkdir -p "$work/public/mascots" site/public/crew
    hand=$(python3 -I - site/out/_next/static <<'PY'
import glob, re, sys
for css in glob.glob(f'{sys.argv[1]}/chunks/*.css'):
    for face in re.findall(r'@font-face\{[^}]*\}', open(css).read()):
        if 'Caveat' in face and 'range:U+??' in face:
            print(re.search(r'url\([^)]*/media/([^)]+\.woff2)\)', face).group(1))
            sys.exit()
sys.exit('No latin Caveat in the build.')
PY
)
    cp "site/out/_next/static/media/$hand" "$work/public/Caveat.woff2"
    cp site/node_modules/geist/dist/fonts/geist-mono/GeistMono-Bold.woff2 "$work/public/"
    cp site/public/mascots/*.svg "$work/public/mascots/"
    # Both rows at work and the pen on what we hold (crew-motion.tsx: NOTES[2]), on nothing.
    for c in CrewMotion:still CrewMotionTall:still-tall; do
        (cd site && npx remotion still motion/index.tsx "${c%%:*}" "$work/${c##*:}.png" --frame=280 --scale=2 \
            --props="{\"base\":\"\",\"tall\":$([ "${c%%:*}" = CrewMotionTall ] && echo true || echo false)}" \
            --public-dir="$work/public" --log=error)
        python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2], quality=86, alpha_quality=90, method=6)' \
            "$work/${c##*:}.png" "site/public/crew/${c##*:}.webp"
    done
    (cd site && npx remotion render motion/index.tsx CrewMotion ../docs/crew.gif --codec=gif --every-nth-frame=4 --scale=0.75 \
        --props='{"base":"","paper":"#f4ecd9"}' --public-dir="$work/public" --log=error --overwrite)
    ls -l site/public/crew docs/crew.gif
    sips -g pixelWidth -g pixelHeight site/public/crew/*.webp docs/crew.gif | grep pixel
    if [ "$(stat -f %z docs/crew.gif)" -gt 5242880 ]; then
        echo "docs/crew.gif is over 5 MB: lower its --scale." >&2
        exit 1
    fi
    ;;
logo)
    # The crew (16×13) and the name (88×12) in one drawing, bottom edges level and four mark pixels
    # apart, as the footer sets them. Shown at four screen pixels to one, every rect stays crisp.
    python3 -I - site/public/mark.svg site/public/logo.svg docs <<'PY'
import re, sys
inner = lambda p: re.sub(r'^.*?<svg[^>]*>|</svg>\s*$', '', open(p).read(), flags=re.S)
mark, name = inner(sys.argv[1]), inner(sys.argv[2])
for out, letters, dots in (('logo.svg', '#23190F', '#B8A685'), ('logo-dark.svg', '#E6EDF3', '#6E6553')):
    drawn = name.replace('#23190F', letters).replace('#B8A685', dots)
    open(f'{sys.argv[3]}/{out}', 'w').write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 13" width="432" height="52" shape-rendering="crispEdges">'
        f'<g>{mark}</g><g transform="translate(20 1)">{drawn}</g></svg>\n')
PY
    ls -l docs/logo.svg docs/logo-dark.svg
    ;;
webicons)
    # The crew of site/public/mark.svg for browsers: favicon.ico (32 and 16, the mark on nothing, one
    # mark pixel to two pixels and to one) and apple-touch-icon.png (180, on its black, which
    # the phone rounds). Every mark pixel lands on whole pixels.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    shot() { # size, background, mark width, left, top, out
        printf '<!doctype html><style>html,body{margin:0;background:%s}svg{position:absolute;left:%spx;top:%spx;width:%spx}</style>%s' \
            "$2" "$4" "$5" "$3" "$(cat site/public/mark.svg)" > "$work/$6.html"
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$work/profile" \
            --hide-scrollbars --default-background-color=00000000 --window-size="$1,$1" \
            --screenshot="$work/$6.png" "file://$work/$6.html" 2>/dev/null
    }
    shot 180 '#141010' 144 18 32 touch
    shot 32 transparent 32 0 3 f32
    shot 16 transparent 16 0 2 f16
    cp "$work/touch.png" site/public/apple-touch-icon.png
    python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[3], sizes=[(32, 32), (16, 16)], append_images=[Image.open(sys.argv[2])])' \
        "$work/f32.png" "$work/f16.png" site/public/favicon.ico
    ls -l site/public/apple-touch-icon.png site/public/favicon.ico
    ;;
icon)
    # The crew of site/public/mark.svg on a black tile, on Apple's 1024 grid: an 824 tile with 185
    # corners. Every pixel of the mark is 40 points and lands on whole pixels down to 128.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    cat > "$work/icon.html" <<HTML
<!doctype html><style>html,body{margin:0;background:transparent}
i{position:absolute;left:100px;top:100px;width:824px;height:824px;border-radius:185px;background:#141010}
svg{position:absolute;left:192px;top:248px;width:640px;height:520px}</style><i></i>$(cat site/public/mark.svg)
HTML
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$work/profile" \
        --hide-scrollbars --default-background-color=00000000 --window-size=1024,1024 \
        --screenshot="$work/1024.png" "file://$work/icon.html" 2>/dev/null
    mkdir "$work/AppIcon.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$work/1024.png" --out "$work/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$work/1024.png" --out "$work/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$work/AppIcon.iconset" -o AppIcon.icns
    ls -l AppIcon.icns
    ;;
check)
    page=site/out/index.html
    fail=0
    npm --prefix site ci --silent
    npm --prefix site test --silent || fail=1
    npm --prefix site run build --silent >/dev/null || { echo "build failed"; exit 1; }
    # 1. The page's words against the copy deck, in checkouts that keep one.
    if [ -x testing/copy-check.sh ]; then testing/copy-check.sh "$page" || fail=1; fi
    # 2. Every file the page points to is there.
    while IFS= read -r ref; do
        [ -e "site/out/${ref#/}" ] || { echo "missing file: $ref"; fail=1; }
    done < <(grep -oE '(src|href)="[^"#:]+"|url\([^):]+\)' "$page" | sed -E 's/^(src|href)="//; s/"$//; s/^url\(//; s/\)$//' | sort -u)
    # 3. Nothing is loaded from another site: links may leave, resources may not. The canonical
    #    link and the funnies' feed link name the site's own addresses and load nothing.
    if grep -oE '<[^>]+>' "$page" | grep -E '(src|srcset)="https?:|url\(["'"'"']?https?:|<link[^>]+href="https?:' | grep -vE 'rel="(canonical|alternate)"'; then
        echo "external resource"; fail=1
    fi
    # 4. In a browser: the head and SEO, Copy, the notch, History, motion, no scripts, every
    #    width, and WCAG AAA (site/e2e).
    npm --prefix site run e2e --silent >/dev/null || { echo "browser tests failed: npm --prefix site run e2e"; fail=1; }
    [ "$fail" = 0 ] && echo "site check: ok"
    exit "$fail"
    ;;
serve)
    serve_out 8765
    ;;
*)
    sed -n '2,/^set /p' "$0" | sed '$d'
    exit 1
    ;;
esac
