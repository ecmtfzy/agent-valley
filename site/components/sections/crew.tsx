import { Face } from '@/components/face';
import { Mascot, Mug, type Person } from '@/components/mascot';
import { Word } from '@/components/word';

// A session's own agent is one of four people; the other types have one face each. Under the
// type, the names the crew go by.
const TYPES: { faces: Person[]; label: string; who: string }[] = [
  { faces: ['guru', 'walrus', 'engineer', 'pearls'], label: 'Session', who: 'Sunny, Walt, Norm or Pearl' },
  { faces: ['coder'], label: 'Plan', who: 'Judy' },
  { faces: ['afro'], label: 'Explore', who: 'Faye' },
  { faces: ['beatnik'], label: 'General-purpose', who: 'Felix' },
];

export function Crew() {
  return (
    <section className="wrap section crew pt-[clamp(72px,14vw,128px)] pb-[clamp(64px,12vw,112px)]">
      <h2>Meet the crew.</h2>
      <p className="mt-[18px] max-w-[34em] text-[1.1875rem] leading-[1.55]">
        Every agent is a programmer from the early days of computing. The face tells you the type. The pose tells you the state.
      </p>
      <h3 className="sr">Types</h3>
      <ul className="types" role="list">
        {TYPES.map((type) => (
          <li key={type.label}>
            {type.faces.length > 1 ? (
              <span className="faces4">{type.faces.map((who) => <Face key={who} who={who} />)}</span>
            ) : (
              <Face who={type.faces[0]} />
            )}
            <span className="label">{type.label}<span className="who">{type.who}</span></span>
          </li>
        ))}
      </ul>
      <h3 className="sr">States</h3>
      <ul className="states" role="list">
        {/* Each line is one span, so the link inside it stays on the line rather than stacking. */}
        <li><Mascot who="guru" pose="work" /><span>Working — <Word id="bob">bobs</Word> and blinks</span></li>
        <li><Mascot who="guru" pose="wave" /><span>Needs you — waves</span></li>
        <li><Mascot who="guru" pose="quiet" /><span>Quiet — looks away</span></li>
        <li><Mascot who="guru" pose="done" /><span>Done — eyes closed</span></li>
      </ul>
      <p className="coffee"><span className="tile"><Mug /></span>Nothing running? Just a cup of coffee.</p>
    </section>
  );
}
