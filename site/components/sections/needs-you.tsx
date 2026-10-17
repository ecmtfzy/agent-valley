import { NeedsYouLoop } from '@/components/needs-you-loop';
import { Word } from '@/components/word';

// A small square in the accent colour marks each point.
const TICK = "relative pl-[1.4em] before:absolute before:top-[.62em] before:left-[.15em] before:size-[.5em] before:bg-accent-text before:content-['']";

export function NeedsYou() {
  return (
    <section className="wrap section split needs-you">
      <div className="stack">
        <h2>Know the moment one needs you.</h2>
        <p className="lead">
          When an agent asks a question or waits for permission, a red count appears beside the <Word id="notch">notch</Word>. Open the panel to read the question or the command.
        </p>
        <ul className="max-w-[36em] space-y-3.5" role="list">
          <li className={TICK}>
            <Word id="jump">Jump</Word> to its app in one click. Turn on Go to the session&apos;s tab, and Terminal and iTerm2 open the exact tab. Ghostty does too, unless two sessions run in the same folder.
          </li>
          <li className={TICK}>
            Answer Claude Code from the notch with Allow once or Deny, using a <Word id="plugin">plugin</Word> you install yourself.
          </li>
          <li className={TICK}>Sounds stay off until you turn them on.</li>
        </ul>
      </div>
      {/* The app's own panel, drawn by testing/site.sh needs-you: a still, and over it the motion
          once the page may move. */}
      <figure
        className="s-figure min-w-0"
        role="img"
        aria-label="The bar beside the notch, while three agents work. One asks to run git push origin preview, and a red 1 appears. The pointer opens the panel on the request and presses Allow once, and the agent goes back to work."
      >
        <img className="s-still" src="/needs-you/still.webp" width={1500} height={1125} alt="" loading="lazy" decoding="async" />
        <NeedsYouLoop />
      </figure>
    </section>
  );
}
