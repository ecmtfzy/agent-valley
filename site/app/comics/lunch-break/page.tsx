import type { Metadata } from 'next';
import { Footer } from '@/components/sections/footer';
import { Nav } from '@/components/sections/nav';

const PAGE = 'https://agentvalley.app/comics/lunch-break/';
const TITLE = 'Lunch break: Claude Code waits for permission while you eat';
const DESCRIPTION =
  'A four-panel comic about Claude Code asking to run npm install a minute after you leave for lunch, and how to stop it waiting an hour for you.';

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: PAGE },
  openGraph: {
    type: 'article',
    url: PAGE,
    title: TITLE,
    description: DESCRIPTION,
    images: [{ url: 'https://agentvalley.app/comics/lunch-break-og.jpg', width: 1200, height: 630 }],
  },
  twitter: { card: 'summary_large_image' },
};

// What the four panels say, for anyone who can't see the picture and for search engines.
const PANELS = [
  ['12:00', 'Sunny, at the desk: “You’re at lunch? I’ll have the refactor done before you’re back.”'],
  ['12:01', 'Sunny points at a dialog on the screen: “First, may I run npm install?”'],
  ['12:40', 'Sunny stands by the empty chair, waving.'],
  ['1:05', 'Sunny, still waving: “I switched arms at half past.”'],
];

const H2 = 'mt-14 mb-4 text-[clamp(1.5rem,3vw,2rem)]';
const CODE = 'rounded bg-card px-1 font-mono text-[.9em]';

export default function LunchBreak() {
  return (
    <>
      <Nav sub />
      <main className="wrap pb-24">
        <article className="mx-auto max-w-[44rem] pt-12">
          <p className="font-mono text-sm text-muted-foreground">A crew comic</p>
          <h1 className="mt-3">Lunch break</h1>
          <p className="lead mt-5">
            You leave Claude Code with a refactor and go to lunch. A minute later it asks to run a command, and then it
            waits for you the whole hour.
          </p>

          <figure className="mt-10">
            <img
              className="w-full rounded-lg border"
              src="/comics/lunch-break-1024.webp"
              srcSet="/comics/lunch-break-1024.webp 1024w, /comics/lunch-break.webp 2048w"
              sizes="(min-width: 760px) 704px, calc(100vw - 32px)"
              width={2048}
              height={2144}
              alt="Four-panel pixel-art comic. Sunny, a bearded programmer in round amber glasses and an orange tie-dye shirt, asks for permission at noon and is still waiting by an empty chair after one o’clock. The words are below."
            />
            <figcaption className="mt-6">
              <h2 className="font-mono text-base tracking-normal">What they say</h2>
              <ol className="mt-3 space-y-2" role="list">
                {PANELS.map(([time, line]) => (
                  <li key={time} className="grid grid-cols-[4.5rem_1fr] gap-3">
                    <span className="font-mono text-muted-foreground">{time}</span>
                    <span>{line}</span>
                  </li>
                ))}
              </ol>
            </figcaption>
          </figure>

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
          <pre className="mt-4 overflow-x-auto rounded-lg border bg-card p-4 font-mono text-sm leading-relaxed" tabIndex={0} aria-label="An allow rule for npm install">
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

          <div className="mt-14 rounded-xl border bg-card p-6">
            <p className="font-semibold">AgentValley is free and open source.</p>
            <p className="mt-2 text-muted-foreground">A small valley of programmers in your notch. Needs macOS 15 or later and Claude Code.</p>
            <p className="mt-4 flex flex-wrap gap-x-6 gap-y-2 font-mono text-sm">
              <a className="inline-flex min-h-11 items-center" href="/#install">Install it</a>
              <a className="inline-flex min-h-11 items-center" href="https://github.com/morsechimwai/agent-valley">Read the code on GitHub</a>
            </p>
          </div>
        </article>
      </main>
      <Footer />
    </>
  );
}
