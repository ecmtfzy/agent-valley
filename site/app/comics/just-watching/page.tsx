import { CODE, ComicPage, H2, PRE, comicMetadata } from '../comic-page';

export const metadata = comicMetadata('just-watching');

export default function JustWatching() {
  return (
    <ComicPage slug="just-watching">
      <h2 className={H2}>Two moments</h2>
      <p>
        A long Claude Code turn needs you at two moments: when it stops to ask, for a permission or an answer, and when
        it finishes. In between, it reads files, edits them and runs commands on its own, as far as your permissions
        let it. Watching that part doesn&apos;t make it faster. It only moves your own work to tomorrow.
      </p>

      <h2 className={H2}>Hear about them</h2>
      <p>
        Claude Code can tell you itself. In Ghostty, Kitty and iTerm2 it can post a Mac notification when it needs you.
        A Notification hook runs a command of yours when it waits for a permission or for input, and a Stop hook runs
        one each time it finishes answering. This one plays a sound:
      </p>
      <pre className={PRE} tabIndex={0} aria-label="A Stop hook that plays a sound">
        {`{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "afplay /System/Library/Sounds/Glass.aiff"
          }
        ]
      }
    ]
  }
}`}
      </pre>
      <p className="mt-4">
        Put it in <code className={CODE}>~/.claude/settings.json</code>, and <code className={CODE}>/hooks</code> lists
        it. A Stop hook runs at the end of every answer, the short ones too, so expect a sound for each.
      </p>

      <h2 className={H2}>Or keep it in the corner of your eye</h2>
      <p>
        <a href="/">AgentValley</a> puts every Claude Code session in your Mac&apos;s notch, one pixel programmer each.
        While a session works, its programmer holds what it&apos;s on: a keyboard for an edit, a terminal for a
        command. It waves when the session needs you, and its eyes close when it&apos;s done. Turn on Sounds in the
        settings for a sound at both moments. A session that finishes in under 30 seconds stays quiet.
      </p>
      <p className="mt-4">
        That works while you&apos;re at the Mac, sketching in the window underneath. For time away from the desk, see{' '}
        <a href="/comics/lunch-break/">Lunch break</a>.
      </p>
    </ComicPage>
  );
}
