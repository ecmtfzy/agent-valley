'use client';

import { useEffect, useState } from 'react';
import { elapsed } from '@/lib/clock';

// A running time that counts up a second at a time from `from` seconds, as the app's rows do.
// It holds while motion is reduced or the page's Stop is pressed; without scripts it reads `from`.
export function Clock({ from }: { from: number }) {
  const [seconds, setSeconds] = useState(from);
  useEffect(() => {
    const moving = matchMedia('(prefers-reduced-motion: no-preference)');
    const tick = setInterval(() => {
      if (moving.matches && !document.documentElement.classList.contains('still')) setSeconds((s) => s + 1);
    }, 1000);
    return () => clearInterval(tick);
  }, []);
  return <span className="clock">{elapsed(seconds)}</span>;
}
