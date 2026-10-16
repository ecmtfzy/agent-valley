#!/bin/bash
# The website in site/: makes its pictures, checks it and serves it on this Mac.
#
#   testing/site.sh mascots   Writes every person and the mug as SVG to site/mascots, from the
#                             app's own cells and colours (SiteMascotsTests).
#   testing/site.sh og        Saves the top of the page at 1200×630 as site/og.png, the picture
#                             a link to the site shows where it is shared.
#   testing/site.sh icon      Writes AppIcon.icns, the app's icon, from site/mark.svg.
#   testing/site.sh check     Every line of the spec's copy is on the page, every file it points
#                             to is there, and nothing is loaded from another site.
#   testing/site.sh serve     Serves site/ at http://localhost:8765 for a browser.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
mascots)
    mkdir -p site/mascots
    SITE_MASCOTS_OUT="$PWD/site/mascots" swift test --filter SiteMascotsTests
    ls site/mascots | wc -l
    ;;
og)
    python3 -m http.server 8766 --bind 127.0.0.1 --directory site >/dev/null 2>&1 &
    server=$!
    disown "$server"
    profile=$(mktemp -d)
    trap 'kill $server; rm -rf "$profile"' EXIT
    sleep 1
    # A profile of its own, so the person's open Chrome is not the one asked.
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$profile" \
        --hide-scrollbars --force-prefers-reduced-motion --virtual-time-budget=3000 \
        --window-size=1200,630 --screenshot="$PWD/site/og.png" "http://127.0.0.1:8766/" 2>/dev/null
    sips -g pixelWidth -g pixelHeight site/og.png | tail -2
    ;;
icon)
    # The crew of site/mark.svg on a black tile, on Apple's 1024 grid: an 824 tile with 185
    # corners. Every pixel of the mark is 40 points and lands on whole pixels down to 128.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    cat > "$work/icon.html" <<HTML
<!doctype html><style>html,body{margin:0;background:transparent}
i{position:absolute;left:100px;top:100px;width:824px;height:824px;border-radius:185px;background:#141010}
svg{position:absolute;left:192px;top:248px;width:640px;height:520px}</style><i></i>$(cat site/mark.svg)
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
    page=site/index.html
    fail=0
    [ -f "$page" ] || { echo "missing page: $page"; exit 1; }
    # 1. The page's words against the copy deck, in checkouts that keep one.
    if [ -x testing/copy-check.sh ]; then testing/copy-check.sh "$page" || fail=1; fi
    # 2. Every file the page points to is there.
    while IFS= read -r ref; do
        [ -e "site/$ref" ] || { echo "missing file: $ref"; fail=1; }
    done < <(grep -oE '(src|href)="[^"#:]+"|url\([^):]+\)' "$page" | sed -E 's/^(src|href)="//; s/"$//; s/^url\(//; s/\)$//' | sort -u)
    # 3. Nothing is loaded from another site: links may leave, resources may not.
    if grep -nE '(src|srcset)="https?:|url\(["'"'"']?https?:|<link[^>]+href="https?:' "$page"; then
        echo "external resource"; fail=1
    fi
    # 4. Without scripts there is no Copy button that does nothing: one hidden button per command.
    [ "$(grep -o '<button class="copy" type="button" hidden' "$page" | wc -l)" = "$(grep -o '<div class="command">' "$page" | wc -l)" ] || { echo "a Copy button is not hidden"; fail=1; }
    [ "$fail" = 0 ] && echo "site check: ok"
    exit "$fail"
    ;;
serve)
    exec python3 -m http.server 8765 --bind 127.0.0.1 --directory site
    ;;
*)
    sed -n '2,/^set /p' "$0" | sed '$d'
    exit 1
    ;;
esac
