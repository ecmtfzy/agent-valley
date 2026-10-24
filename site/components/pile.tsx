'use client';

import { useEffect, useRef } from 'react';

// Where the section is held (set-pieces.css), as Apple's pages hold one while it plays.
const HELD = '(min-width: 900px) and (min-height: 640px)';
// Held: from the section's top halfway down the screen to its end.
const FROM = 0.5;

// The old pop's spring, now under the reader's hand: up a little past its place, then settled.
const spring = (t: number) => 1 + 2.70158 * (t - 1) ** 3 + 1.70158 * (t - 1) ** 2;

// A pile of terminals that grows with the scroll. Each terminal comes up over its own stretch of
// the scroll and goes back down the same way, so the pile moves whenever the page does: `--t` is how
// far up it is (0 to 1), `--e` the same with the spring on it, and the CSS draws from both. Held,
// the pile fills over the section's height, all five up with a fifth of it left; otherwise, as the
// picture rises from the foot of the screen to its middle.
export function Pile({ label, children }: { label: string; children: React.ReactNode }) {
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const pile = box.current!;
    const section = pile.closest('section')!;
    const held = matchMedia(HELD);
    const terms = [...pile.querySelectorAll<HTMLElement>('.term')];
    let frame = 0;
    const look = () => {
      frame = 0;
      const h = innerHeight;
      let done: number;
      if (held.matches) {
        const { top, height } = section.getBoundingClientRect();
        done = (FROM * h - top) / (height - h + FROM * h);
      } else {
        done = (0.9 * h - pile.getBoundingClientRect().top) / (0.5 * h);
      }
      // Terminal i is all the way up where the old pile called it, at done = i / count; `data-n`
      // says how many are all the way up.
      const up = done * terms.length + 1;
      terms.forEach((term, i) => {
        const t = Math.min(1, Math.max(0, up - i));
        term.style.setProperty('--t', t.toFixed(3));
        term.style.setProperty('--e', spring(t).toFixed(3));
      });
      pile.dataset.n = String(Math.min(terms.length, Math.max(0, Math.floor(up))));
    };
    const soon = () => {
      frame ||= requestAnimationFrame(look);
    };
    look();
    addEventListener('scroll', soon, { passive: true });
    addEventListener('resize', soon);
    return () => {
      removeEventListener('scroll', soon);
      removeEventListener('resize', soon);
      cancelAnimationFrame(frame);
    };
  }, []);
  return (
    <div className="terms" ref={box} role="img" aria-label={label}>
      {children}
    </div>
  );
}
