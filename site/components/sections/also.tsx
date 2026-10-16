import { Word } from '@/components/word';

type Item = { term: string; text: React.ReactNode };

// A spec sheet, not a row of cards: ruled lines, two across on a wide screen.
function Sheet({ items }: { items: Item[] }) {
  return (
    <dl className="grid border-t min-[760px]:grid-cols-2 min-[760px]:gap-x-14">
      {items.map((item) => (
        <div key={item.term} className="grid content-start gap-1.5 border-b py-[22px]">
          <dt className="font-mono font-semibold">{item.term}</dt>
          <dd className="max-w-[36em] text-[.9375rem] text-muted-foreground">{item.text}</dd>
        </div>
      ))}
    </dl>
  );
}

export function Also() {
  return (
    <section className="wrap section more py-[clamp(56px,10vw,88px)]">
      <h2 className="mb-7">Also in the panel.</h2>
      <Sheet
        items={[
          { term: 'Plan limits', text: 'Your Claude 5-hour and weekly limits, with time left until reset. Off until you turn it on.' },
          { term: 'Token use', text: <><Word id="tokens">Tokens</Word> for the last 5 hours and today, with a 12-hour chart.</> },
          { term: 'Keyboard', text: <>Press <abbr title="Control-Option-Command-A">⌃⌥⌘A</abbr> from any app. Arrows to pick, Return to jump.</> },
        ]}
      />
    </section>
  );
}
