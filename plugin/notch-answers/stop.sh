#!/bin/sh
# Hands Claude Code's Stop event to the AgentValley notch app and prints its answer, if any.
#
# While the app holds the person as Away, it may answer with a block decision and the text to
# continue with. With no app, or an empty answer from it, this prints nothing and always exits 0,
# so Claude Code ends its turn as usual. It waits only while the app holds the turn.
DIR="$HOME/Library/Application Support/AgentValley"
SOCK="$DIR/answers.sock"
[ -S "$SOCK" ] || exit 0
# The app keeps this file there only while Away is on; any other time the turn ends at once.
[ -e "$DIR/away" ] || exit 0
# -q first: the person's own ~/.curlrc must not add anything to what is printed here.
/usr/bin/curl -q --silent --fail --max-time 86390 --unix-socket "$SOCK" \
  --header 'Content-Type: application/json' --data-binary @- \
  http://notch/stop-wait 2>/dev/null
exit 0
