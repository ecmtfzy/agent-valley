import { CODE, ComicPage, H2, comicMetadata } from '../comic-page';

export const metadata = comicMetadata('typo-case');

export default function TypoCase() {
  return (
    <ComicPage slug="typo-case">
      <h2 className={H2}>The typo was cheap. The conversation wasn&apos;t.</h2>
      <p>
        Claude Code&apos;s docs put it in one line: token costs scale with context size. Each new message is read along
        with the conversation before it. Ask for a one-word fix at the end of a long session, and Claude reads the whole
        session again to make it.
      </p>
      <p className="mt-4">
        Prompt caching helps. Claude Code turns it on for you, so the part of the conversation it has already seen
        costs less to read again. Less is not nothing, and a long session still makes every small question a big one.
      </p>

      <h2 className={H2}>Keep small tasks small</h2>
      <ul className="mt-4 list-disc space-y-3 pl-6">
        <li>
          <code className={CODE}>/clear</code> starts fresh. Use it when you move on to work that has nothing to do with
          the last task, typos included.
        </li>
        <li>
          <code className={CODE}>/compact</code> boils the conversation down to a summary, and you can tell it what to
          keep: <code className={CODE}>/compact Focus on the auth changes</code>.
        </li>
        <li>
          <code className={CODE}>/model</code> switches models in the middle of a session, so a spelling fix need not
          go to the biggest model you have.
        </li>
        <li>
          <code className={CODE}>/context</code> draws what fills the context as a colored grid, before you send the
          next message.
        </li>
      </ul>

      <h2 className={H2}>Start at the last page</h2>
      <p>
        Pearl reads the total first, then works back to find where it went. On an API key,{' '}
        <code className={CODE}>/usage</code> shows what the session has cost so far. For the days and weeks behind you, <a href="/">AgentValley</a>&apos;s
        History, in the notch panel, shows what each project cost at API prices, by day, week or month, down to its
        sessions. It keeps the numbers on your Mac after Claude Code clears its old files, and hands a month over as a
        PDF.
      </p>
    </ComicPage>
  );
}
