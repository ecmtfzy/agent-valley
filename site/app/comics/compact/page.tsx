import { CODE, ComicPage, H2, PRE, comicMetadata } from '../comic-page';

export const metadata = comicMetadata('compact');

export default function Compact() {
  return (
    <ComicPage slug="compact">
      <h2 className={H2}>What goes in the box</h2>
      <p>
        When a conversation reaches the model&apos;s context limit, Claude Code compacts it: it summarizes the history
        so far so the session can go on. <code className={CODE}>/compact</code> does the same when you ask for it.{' '}
        <code className={CODE}>/clear</code> is the other way out, a new conversation with empty context.
      </p>
      <p className="mt-4">
        A summary is shorter than what it sums up. A decision from an hour ago, or the name of the thing you are
        building, can be left out of it.
      </p>

      <h2 className={H2}>Tell it what to keep</h2>
      <p>
        <code className={CODE}>/compact</code> takes focus instructions:{' '}
        <code className={CODE}>/compact Focus on the login flow</code> keeps the summary on that.
      </p>
      <p className="mt-4">
        What must outlast every summary belongs in <code className={CODE}>CLAUDE.md</code>. After compaction, Claude
        Code reads the <code className={CODE}>CLAUDE.md</code> at the root of the project from disk again, so what you
        are building, and how to test it, come back each time. It can also hold a line for the summaries themselves:
      </p>
      <pre className={PRE} tabIndex={0} aria-label="A line for CLAUDE.md">
        {`When compacting, always preserve the full list of modified files and any test commands.`}
      </pre>

      <h2 className={H2}>Watch the gauge</h2>
      <p>
        <code className={CODE}>/context</code> draws what fills the context as a colored grid, with warnings as it gets
        full. A custom status line gets the number from Claude Code as{' '}
        <code className={CODE}>context_window.used_percentage</code>, and <a href="/">AgentValley</a>&apos;s status line
        draws it as a bar, next to the five-hour and weekly limits. To move the point where it compacts,{' '}
        <code className={CODE}>/autocompact</code> sets the window in tokens, from 100K to 1M:{' '}
        <code className={CODE}>/autocompact 500k</code>.
      </p>
    </ComicPage>
  );
}
