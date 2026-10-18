'use client';

import { useEffect, useState } from 'react';
import { announce } from '@/components/announcer';
import { Pumpkin } from '@/components/mascot';
import { cn } from '@/lib/utils';
import { found, HUNT, light } from '@/lib/pumpkins';

const OF = 'of 5 found';

// How many the visitor has lit, kept up to date by every pumpkin on the page.
function useFound() {
  const [lit, setLit] = useState<number[]>([]);
  useEffect(() => {
    const sync = () => setLit(found());
    sync();
    addEventListener('pumpkins', sync);
    return () => removeEventListener('pumpkins', sync);
  }, []);
  return lit;
}

// One of the five, unlit until pressed. A 44-point target round a small pumpkin.
export function HuntPumpkin({ n, className }: { n: number; className?: string }) {
  const lit = useFound().includes(n);
  return (
    <button
      type="button"
      className={cn('hunt hw', className)}
      aria-label="Pumpkin"
      aria-pressed={lit}
      onClick={() => {
        const all = light(n).length;
        announce(all === HUNT ? 'All five lit. Check our photo at the bottom of the page.' : `Pumpkin lit. ${all} ${OF}.`);
      }}
    >
      <Pumpkin lit={lit} />
    </button>
  );
}

// The top bar's count, from the first one found; at five it leads to the crew's new photo.
export function PumpkinCount() {
  const n = useFound().length;
  if (!n) return null;
  const words = (
    <>
      <Pumpkin />
      <span className="min-[640px]:hidden" aria-hidden="true">{n}</span>
      <span className="max-[640px]:sr-only">{n} {OF}</span>
    </>
  );
  return n === HUNT ? <a className="hunt-count hw" href="#crew-photo">{words}</a> : <span className="hunt-count hw">{words}</span>;
}
