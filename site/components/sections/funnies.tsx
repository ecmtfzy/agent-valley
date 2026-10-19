import { masthead } from '@/app/fonts';
import { STRIPS } from '@/app/comics/strips';
import '@/app/comics/funnies.css';

// Near the end, a cutting from the Sunday paper: its name, its dateline and three strips, each with
// what its page tells, then the way to the rest. The three show the app's own moments: an agent
// waiting, a sub-agent at work, a tab left asking.
const PICKS = ['lunch-break', 'explore', 'tab-7'];

export function Funnies() {
  const picks = PICKS.map((slug) => ({ strip: STRIPS.find((s) => s.slug === slug)!, n: STRIPS.findIndex((s) => s.slug === slug) + 1 }));
  return (
    <section className="wrap section pt-[clamp(56px,10vw,96px)]" id="funnies" aria-labelledby="funnies-name">
      <div className={`funnies cutting ${masthead.variable}`}>
        <h2 id="funnies-name" className="f-name">
          The Valley Funnies
        </h2>
        <p className="f-date">
          <span>Vol. I, No. {STRIPS.length}</span>
          <span>Comics about working with Claude Code</span>
          <span>Price: free</span>
        </p>
        <p className="fc-lead">Between sessions we draw comics about the job. Each one comes with the story behind it.</p>
        <ul className="fc-picks" role="list">
          {picks.map(({ strip, n }) => (
            <li key={strip.slug}>
              <article className="f-card" aria-labelledby={`pick-${strip.slug}`}>
                <img className="f-strip" src={`/comics/${strip.slug}-640.webp`} width={640} height={670} alt={strip.alt} loading="lazy" decoding="async" />
                <div>
                  <p className="f-kicker">No. {n} · Starring {strip.starring}</p>
                  <h3 id={`pick-${strip.slug}`} className="f-head">
                    <a href={`/comics/${strip.slug}/`}>{strip.title}</a>
                  </h3>
                  <p className="f-deck">{strip.deck}</p>
                  <p className="f-inside">{strip.inside}</p>
                </div>
              </article>
            </li>
          ))}
        </ul>
        <p className="fc-more">
          <a href="/comics/">Read all {STRIPS.length} strips</a>
        </p>
      </div>
    </section>
  );
}
