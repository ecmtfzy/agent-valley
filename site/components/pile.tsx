'use client';

import { useEffect, useRef } from 'react';

// Where the section is held (set-pieces.css), as Apple's pages hold one while it plays.
const HELD = '(min-width: 900px) and (min-height: 640px)';
// Held: from the section's top halfway down the screen to its end.
const FROM = 0.5;

// A pile of terminals that grows with the scroll: `data-n` says how many are up, and the CSS pops
// each one in as it is called. Held, the pile fills over the section's height, all five up with a
// fifth of it left; otherwise, as the picture rises from the foot of the screen to its middle.
export function Pile({ label, children }: { label: string; children: React.ReactNode }) {
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const pile = box.current!;
    const section = pile.closest('section')!;
    const held = matchMedia(HELD);
    const count = pile.querySelectorAll('.term').length;
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
      pile.dataset.n = String(Math.min(count, Math.max(0, Math.floor(done * count) + 1)));
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
