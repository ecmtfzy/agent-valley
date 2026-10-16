'use client';

import { useEffect, useState } from 'react';
import { Icon } from '@/components/icons';
import { Button } from '@/components/ui/button';

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
  // The icon alone on the bar; its words show on hover and stay for screen readers.
  return (
    <Button
      type="button"
      variant="ghost"
      hidden={!ready}
      onClick={flip}
      title={label}
      className="still-toggle size-11 p-0 text-muted-foreground hover:bg-transparent hover:text-foreground motion-reduce:hidden"
    >
      <span className="grid size-8 place-items-center rounded-full border border-border">
        <Icon id={still ? 'play' : 'pause'} />
      </span>
      <span className="sr-only">{label}</span>
    </Button>
  );
}
