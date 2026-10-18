import { CODE, ComicPage, H2, comicMetadata } from '../comic-page';

export const metadata = comicMetadata('plan-mode');

export default function PlanMode() {
  return (
    <ComicPage slug="plan-mode">
      <h2 className={H2}>What plan mode does</h2>
      <p>
        In plan mode, Claude Code reads files and runs shell commands to look around, then writes a plan. It does not
        edit your code until you approve one. Press <code className={CODE}>Shift+Tab</code> to get there, put{' '}
        <code className={CODE}>/plan</code> in front of a single prompt, or start a session with{' '}
        <code className={CODE}>claude --permission-mode plan</code>. <code className={CODE}>Shift+Tab</code> again
        leaves without approving anything.
      </p>
      <p className="mt-4">
        To gather what the plan needs, Claude can send the Plan sub-agent, a read-only research agent. In{' '}
        <a href="/">AgentValley</a> that sub-agent gets its own row under the session in the notch, with Judy&apos;s
        face.
      </p>

      <h2 className={H2}>When to skip the plan</h2>
      <p>
        Claude Code&apos;s best practices have a rule for it: if you could describe the diff in one sentence, skip the
        plan. Their examples are a typo, a log line and a rename. <q>Rename one button</q> is one sentence, so ask for
        the change itself. Plan when you are not sure how the change should go.
      </p>

      <h2 className={H2}>When the plan arrives anyway</h2>
      <p>Claude Code shows the plan and asks what to do with it:</p>
      <ul className="mt-4 list-disc space-y-3 pl-6">
        <li>
          <q>Yes, and use auto mode</q> (or <q>Yes, auto-accept edits</q>) approves it and hands the edits to Claude.
        </li>
        <li>
          <q>Yes, manually approve edits</q> approves it and asks you before each edit.
        </li>
        <li>
          <q>No, keep planning</q> sends it back for another round.
        </li>
      </ul>
      <p className="mt-4">
        <code className={CODE}>Ctrl+G</code> opens the plan in your text editor, where you can change it before you
        approve. Thirty-seven steps are quick to delete.
      </p>
    </ComicPage>
  );
}
