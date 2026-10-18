import { CODE, ComicPage, H2, PRE, comicMetadata } from '../comic-page';

export const metadata = comicMetadata('last-prompt');

export default function LastPrompt() {
  return (
    <ComicPage slug="last-prompt">
      <h2 className={H2}>Two limits, not one</h2>
      <p>
        Claude Pro and Max plans give Claude Code a five-hour session limit and a weekly limit. The five-hour one clears
        within hours. The weekly one resets once a week, so at 98 percent on a Tuesday, the rest of the week is
        what you have left.
      </p>
      <p className="mt-4">
        In Claude Code, <code className={CODE}>/usage</code> shows your plan&apos;s usage limits, with the session&apos;s
        cost and activity stats. <code className={CODE}>/cost</code> and <code className={CODE}>/stats</code> open the
        same view.
      </p>

      <h2 className={H2}>Keep the numbers in view</h2>
      <p>
        A custom status line gets both limits from Claude Code as{' '}
        <code className={CODE}>rate_limits.five_hour.used_percentage</code> and{' '}
        <code className={CODE}>rate_limits.seven_day.used_percentage</code>, with the time each resets. They arrive for
        Pro and Max plans, after the session&apos;s first answer.
      </p>
      <p className="mt-4">
        <a href="/">AgentValley</a> draws them for you. Its status line puts bars for context, the five-hour limit and
        the weekly limit under the prompt, and Plan limits in the notch panel shows both with the time left until each
        resets. Plan limits stays off until you turn it on.
      </p>

      <h2 className={H2}>A prompt worth the last two percent</h2>
      <p>
        <q>Fix it</q> leaves Claude to work out what <q>it</q> is. Looking for it takes turns, and turns spend the limit
        you meant for the fix. Claude Code&apos;s own best practices ask for the symptom, the likely place, and what
        fixed looks like, plus a check Claude can run, such as a test or a build:
      </p>
      <pre className={PRE} tabIndex={0} aria-label="A specific prompt">
        {`After a session timeout, login fails with "token expired". The refresh is in @src/auth/session.ts. Fix it so the token refreshes, then run npm test -- auth to check.`}
      </pre>
      <p className="mt-4">
        The <code className={CODE}>@</code> in front of a path hands Claude that file, so it reads it before answering
        instead of searching for it. One small fix with a test that proves it is a better last prompt than a refactor
        that stops halfway when the limit runs out.
      </p>
    </ComicPage>
  );
}
