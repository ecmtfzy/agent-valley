import { CODE, ComicPage, H2, PRE, comicMetadata } from '../comic-page';

export const metadata = comicMetadata('explore');

export default function Explore() {
  return (
    <ComicPage slug="explore">
      <h2 className={H2}>Who Faye is</h2>
      <p>
        Explore is one of the sub-agents that come with Claude Code. Its docs call it a fast, read-only agent for
        searching and analyzing codebases: it reads, and it can&apos;t write or edit. Claude sends it off quick, medium
        or very thorough, depending on the question.
      </p>
      <p className="mt-4">
        <q>Where&apos;s the login button?</q> names no place to look, so the place to look is the whole repository.
        That is the desert in the second panel.
      </p>

      <h2 className={H2}>Hand it the file</h2>
      <p>
        Put <code className={CODE}>@</code> in front of a path, and Claude reads that file before it answers, instead
        of hunting for it:
      </p>
      <pre className={PRE} tabIndex={0} aria-label="A prompt that names the file">
        {`Where's the login button in @Sources/App/ContentView.swift?`}
      </pre>
      <p className="mt-4">
        In an editor it can be shorter still. In VS Code, Claude Code sees the text you select and which file you have
        open, even with nothing selected. In JetBrains IDEs, the current selection or tab is shared with it. Run it
        there, and <q>the file I have open</q> is a place it already knows.
      </p>

      <h2 className={H2}>See the search while it runs</h2>
      <p>
        <a href="/">AgentValley</a> gives every sub-agent a row of its own under its session in the notch, with the task,
        the model and the step it is on, and the row counts its steps. A search that is still going at step 200 is easy
        to spot while it runs, rather than in the bill afterwards.
      </p>
    </ComicPage>
  );
}
