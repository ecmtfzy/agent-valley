'use client';

import { useEffect, useState } from 'react';
import { Icon } from '@/components/icons';

// The loops can be stopped for good, not only by the system's Reduce Motion, and stay stopped on
// the next visit. The layout's first script has already put back a stop from last time.
export function StillToggle() {
  const [ready, setReady] = useState(false);
  const [still, setStill] = useState(false);
  useEffect(() => {
    setStill(document.documentElement.classList.contains('still'));
    setReady(true);
  }, []);

  function flip() {
    const on = !still;
    document.documentElement.classList.toggle('still', on);
    setStill(on);
    try {
      localStorage.setItem('still', on ? '1' : '');
    } catch {}
  }

  const label = still ? 'Play the animations' : 'Stop the animations';
  // In the foot's small print: the page plays on its own, and this is there for whoever needs it to stop.
  return (
    <button type="button" hidden={!ready} onClick={flip} className="still-toggle inline-flex min-h-11 items-center gap-2 hover:text-foreground motion-reduce:hidden">
      <Icon id={still ? 'play' : 'pause'} />
      {label}
    </button>
  );
}
