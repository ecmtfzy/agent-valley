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
#   testing/site.sh photo     Writes docs/crew-photo.webp, the crew photo framed as the site shows it,
#                             for the README.
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
    #    link names the page's own address and loads nothing.
    if grep -oE '<[^>]+>' "$page" | grep -E '(src|srcset)="https?:|url\(["'"'"']?https?:|<link[^>]+href="https?:' | grep -v 'rel="canonical"'; then
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
