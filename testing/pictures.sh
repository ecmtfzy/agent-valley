#!/bin/bash
# Draws the real panel in a window off the screen, over the made-up sessions of demo.py, and
# saves what it looks like and what a screen reader is told of it. It moves no pointer, presses
# no key and puts nothing on the screen, so it can run while you work on this Mac. It is not a
# click or a key on the panel itself.
#
#   testing/pictures.sh [scene ...]   Every scene when none is named. Results in build/pictures.
#     list      the list as it opens
#     status    the same, grouped by status
#     keys      the ring on each session in turn, in both orders
#     idle      the ring on an idle session unfolded from its line
#     intro     the words of the first launch
#     legend    each page of the legend
#     settings  each page of the settings, and the plugin's command with its switch on
#     request   a command to allow and a question to answer, by pointer and by key
#     reader    what a screen reader is told: open, with the ring, in the settings, and shut
#     oldcopy   the line and the settings when Homebrew left our 0.1 installed
#     tokens    the token line at the foot of the list, and what a screen reader is told of it
#     history          the History page in the panel over a made-up month
#     history-project  the same, one project deep
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="/Users/Shared/pt"
FAKE_HOME="$ROOT/pictures"
OUT="$PWD/build/pictures"
SCENES=("$@")
[ ${#SCENES[@]} -gt 0 ] || SCENES=(list status keys idle intro legend settings request reader oldcopy tokens history history-project)

# Every account on this Mac can write to /Users/Shared, so ROOT has to be this user's own
# folder, closed to the others, before anything under it is removed: were it a link someone
# else put there, the fake home would name someone else's folder, and `rm -rf` would empty
# it. The same check as demo.py makes. Once it holds nobody else can swap the folder
# out: /Users/Shared lets only an entry's owner rename or remove it.
own_root() {
    mkdir -p "$ROOT"
    if [ -L "$ROOT" ] || [ ! -d "$ROOT" ] || [ ! -O "$ROOT" ]; then
        echo "$ROOT is a link or belongs to someone else. Remove it and run this again." >&2
        exit 1
    fi
    chmod 700 "$ROOT"
}

own_root
mkdir -p "$OUT"
swiftc -O testing/axdump.swift -o "$OUT/axdump"
# From nothing each time: demo.py adds to the transcripts it finds.
rm -rf "$FAKE_HOME"
python3 testing/demo.py start "$FAKE_HOME" >/dev/null &
DEMO=$!
# The pid file may be shared with another run: taken away only when it is this run's own.
trap 'kill "$DEMO" 2>/dev/null || true
      [ "$(cat "$ROOT/demo.pid" 2>/dev/null)" != "$DEMO" ] || rm -f "$ROOT/demo.pid"
      rm -rf "$FAKE_HOME"' EXIT
sleep 2
for scene in "${SCENES[@]}"; do
    PANEL_PICTURES_HOME="$FAKE_HOME" PANEL_PICTURES_OUT="$OUT" PANEL_PICTURES_AXDUMP="$OUT/axdump" PANEL_PICTURES_SCENE="$scene" \
        swift test --filter PanelPicturesTests 2>&1 | grep -E "error|passed \(|failed" || true
done
echo "Pictures in $OUT"
