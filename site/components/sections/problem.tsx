import { Reveal } from '@/components/reveal';
import { Word } from '@/components/word';

const TERMS = [
  { name: 'api', wait: true, text: 'Allow this command?\ngit push origin main\n1. Yes   2. No' },
  { name: 'docs', text: '> Write docs/api.md\n  Writing section 3 of 5' },
  { name: 'checkout', text: '> Read index.tsx\n> Grep PaymentIntent' },
  { name: 'cart-tests', text: '> Edit cart.test.ts\n  4 tests added' },
  { name: 'shop-web', text: '> Bash npm test\n  112 passed\n> Edit src/cart/total.ts' },
];

export function Problem() {
  return (
    <section className="wrap section split problem pt-[clamp(72px,14vw,128px)] pb-[clamp(64px,12vw,112px)]">
      <div className="stack">
        <h2>Five agents running. Which one is waiting for you?</h2>
        <p className="lead">
          Each <Word id="agent">agent</Word> reports in its own <Word id="terminal">terminal</Word>, line by line. Run a few <Word id="session">sessions</Word> at once and you <Word id="end-up">end up</Word> switching windows just to <Word id="check-on">check on</Word> them.
        </p>
      </div>
      {/* Five terminals, stacked; the one waiting for an answer is at the back. */}
      <Reveal>
        <div className="terms" role="img" aria-label="Five terminal windows stacked on top of one another. The one waiting for an answer is buried at the back.">
          <div className="draw" aria-hidden="true">
            {TERMS.map((t, i) => (
              <div key={t.name} className={t.wait ? 'term wait' : 'term'} style={{ '--i': i } as React.CSSProperties}>
                <header><i /><i /><i /><span>{t.name}</span>{t.wait && <b>waiting</b>}</header>
                <pre>{t.text}</pre>
              </div>
            ))}
          </div>
        </div>
      </Reveal>
    </section>
  );
}
