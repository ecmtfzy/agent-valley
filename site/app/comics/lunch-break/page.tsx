import { CODE, ComicPage, H2, PRE, comicMetadata } from '../comic-page';

export const metadata = comicMetadata('lunch-break');

export default function LunchBreak() {
  return (
    <ComicPage slug="lunch-break">
      <h2 className={H2}>Why it waits</h2>
      <p>
        In its default mode, Claude Code runs read-only commands like <code className={CODE}>ls</code> and{' '}
        <code className={CODE}>git status</code> on its own and asks before any other shell command.{' '}
        <code className={CODE}>npm install</code> downloads packages and runs their install scripts, so it asks. Then
        it keeps the question open until someone answers. No timeout, no default answer.
      </p>

      <h2 className={H2}>Let it run the boring commands</h2>
      <p>
        At the prompt, pick <q>Yes, and don&apos;t ask again</q>. Claude Code saves the rule in{' '}
        <code className={CODE}>.claude/settings.local.json</code> at the root of the repository, and no session in
        that repository asks about it again. To share the rule with your team, put it in{' '}
        <code className={CODE}>.claude/settings.json</code> and commit it:
      </p>
      <pre className={PRE} tabIndex={0} aria-label="An allow rule for npm install">
        {`{
  "permissions": {
    "allow": ["Bash(npm install *)"]
  }
}`}
      </pre>
      <p className="mt-4">
        The <code className={CODE}>*</code> covers <code className={CODE}>npm install</code> on its own and with a
        package name. <code className={CODE}>/permissions</code> lists every rule and the file it came from. Allow the
        boring commands one by one: a rule for all of <code className={CODE}>Bash</code> lets it run anything, which is
        a lot to hand over before lunch.
      </p>

      <h2 className={H2}>Know when it waits</h2>
      <p>
        In Ghostty, Kitty and iTerm2, Claude Code can post a Mac notification when it needs you, and a Notification
        hook can run a command of yours at that moment. With five sessions open, you still have to find the one that
        asked.
      </p>
      <p className="mt-4">
        <a href="/">AgentValley</a> puts every Claude Code session in your Mac&apos;s notch, one pixel programmer
        each. The one waiting for permission waves, and a red count shows beside the notch. Open the panel to read
        the command, and answer Allow once or Deny from the notch with a plugin you install yourself.
      </p>
      <p className="mt-4">
        That helps at the desk. At lunch, your Mac stays in the office, and so does the notch. For lunch there is
        Claude Code&apos;s Remote Control: it can push to the Claude app on your phone when a session needs you, as long
        as the session keeps running on your Mac.
      </p>
    </ComicPage>
  );
}
