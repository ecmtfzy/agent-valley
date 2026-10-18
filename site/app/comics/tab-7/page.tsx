import { CODE, ComicPage, H2, PRE, comicMetadata } from '../comic-page';

export const metadata = comicMetadata('tab-7');

export default function Tab7() {
  return (
    <ComicPage slug="tab-7">
      <h2 className={H2}>Still asking</h2>
      <p>
        In its default mode, Claude Code asks before it runs most shell commands, and the question stays on screen
        until someone answers it. The session does nothing else in the meantime. Leave seven tabs open for a week, and
        one of them can still be on Tuesday&apos;s lunch. <a href="/comics/lunch-break/">Lunch break</a> covers why it
        asks, and how to let it run the boring commands.
      </p>

      <h2 className={H2}>Find the tab that asked</h2>
      <p>
        From the outside, the tab that asked looks like the six that didn&apos;t. A Notification hook can play a sound
        when Claude Code asks for permission, but the sound lasts a second, and the question lasts until someone
        answers.
      </p>
      <p className="mt-4">
        <a href="/">AgentValley</a> puts every Claude Code session in your Mac&apos;s notch, one pixel programmer each.
        The one waiting for permission waves, and a red count shows beside the notch. One click takes you to its app.
        Turn on Go to the session&apos;s tab, and Terminal and iTerm2 open the exact tab. Ghostty does too, unless two
        sessions run in the same folder.
      </p>

      <h2 className={H2}>Get back to the rest</h2>
      <p>
        Closing a tab doesn&apos;t lose the conversation: Claude Code saves each session on your Mac. In the same
        folder, <code className={CODE}>claude --continue</code> opens the most recent one again, and{' '}
        <code className={CODE}>claude --resume</code> lists them with each one&apos;s name, how long ago it was last
        active, and its git branch. Name a session with <code className={CODE}>/rename</code> before you walk away, and
        the list shows it by that name.
      </p>
      <p className="mt-4">
        By default, Claude Code keeps these transcripts for 30 days. To keep them longer, set{' '}
        <code className={CODE}>cleanupPeriodDays</code> in your settings:
      </p>
      <pre className={PRE} tabIndex={0} aria-label="A setting that keeps transcripts for 90 days">
        {`{
  "cleanupPeriodDays": 90
}`}
      </pre>
    </ComicPage>
  );
}
