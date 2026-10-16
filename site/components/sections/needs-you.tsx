import { Mascot } from '@/components/mascot';
import { Reveal } from '@/components/reveal';
import { Word } from '@/components/word';

// A small square in the accent colour marks each point.
const TICK = "relative pl-[1.4em] before:absolute before:top-[.62em] before:left-[.15em] before:size-[.5em] before:bg-accent-text before:content-['']";

export function NeedsYou() {
  return (
    <section className="wrap section split">
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
      {/* The bar as it looks most of the day, and a request it opens to. */}
      <Reveal>
        <figure className="ask" role="img" aria-label="The bar beside the notch: a waving programmer and a red 1. Below it, the request in the panel, the command, with Allow once and Deny.">
          <div className="draw" aria-hidden="true">
            <div className="strip">
              <Mascot who="guru" pose="wave" />
              <span className="count">1</span>
              <span className="gap" />
              <span className="gauge" />
            </div>
            <div className="p-card">
              <Mascot who="guru" pose="wave" dot />
              <div>
                <p className="p-line"><b>Deploy preview build</b><span><em>needs you</em> <span className="model">Sonnet 5.5</span></span></p>
                <p>&gt; Bash git push origin preview</p>
                <p className="answer"><span>Allow once</span><span>Deny</span></p>
              </div>
            </div>
          </div>
        </figure>
      </Reveal>
    </section>
  );
}
