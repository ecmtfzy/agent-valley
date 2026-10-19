'use client';

import { useEffect, useRef } from 'react';

const HELLO = 'Happy Halloween.';
const NOISE = '01!<>/\\[]{}=+*#$%';

// Halloween's band above the top bar, on every page: a line from the crew's terminal. The greeting
// comes up scrambled and decodes itself once, left to right, unless motion is off. It scrolls away;
// the top bar stays.
export function HalloweenBar() {
  const shown = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const el = shown.current;
    const d = document.documentElement;
    if (!el || !d.classList.contains('halloween') || d.classList.contains('still') || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    let frame = 0;
    let id = 0;
    const tick = () => {
      const done = Math.floor(frame++ / 4);
      el.textContent = [...HELLO].map((c, i) => (i < done || c === ' ' ? c : NOISE[(Math.random() * NOISE.length) | 0])).join('');
      if (done < HELLO.length) id = requestAnimationFrame(tick);
    };
    tick();
    return () => {
      cancelAnimationFrame(id);
      el.textContent = HELLO;
    };
  }, []);
  return (
    <aside className="hw hbar" aria-label="Halloween">
      <img src="/pumpkin.svg" alt="" width="16" height="16" loading="lazy" />
      <span className="hb-cmd max-[639px]:hidden" aria-hidden="true">crew@valley:~$ sudo trick-or-treat</span>
      <strong>
        <span ref={shown} aria-hidden="true">{HELLO}</span>
        <span className="sr">{HELLO}</span>
      </strong>
      <a href="/comics/tab-7/">
        Someone’s still in the building<span className="sr">: read the comic Tab 7</span>
        <span aria-hidden="true">{'\u00a0→'}</span>
      </a>
    </aside>
  );
}
