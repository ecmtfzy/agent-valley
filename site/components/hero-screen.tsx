'use client';

import { useEffect, useRef, useState } from 'react';

// The picture's words follow it: open, the panel; shut, the bar.
const TOLD = {
  open: 'The top of a MacBook screen. The AgentValley panel is open under the notch: one session needs you, another is working with two sub-agents. Below, the crew stands in the valley.',
  shut: 'The top of a MacBook screen. Beside the notch, a waving programmer and a red 1: an agent needs you. Below, the crew stands in the valley.',
};

// How long a mouse rests on the bar before the panel opens, as the app waits (EntryWatch.dwell):
// one crossing the bar on its way elsewhere is gone by then.
const DWELL = 100;

// The hero's panel stands open; the bar beside the notch shuts and opens it, by click, tap or
// keyboard. Without scripts the panel stays open and the button stays hidden. With them it waits
// shut for 400 ms and opens once (set-pieces.css), so the reader sees where it comes from; it
// never opens and shuts on its own again. A mouse works it as on a Mac: resting on the bar opens
// it, and once in, leaving the panel shuts it; Esc shuts it too.
export function HeroScreen({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<'open' | 'shut'>('open');
  const [ready, setReady] = useState(false);
  const [opened, setOpened] = useState(false);
  const button = useRef<HTMLButtonElement>(null);
  // Whether the mouse is in the panel or on the bar; whether resting on the bar may open it (not
  // right after it was pressed or Esc'd shut there); and the wait before it opens.
  const inside = useRef(false);
  const armed = useRef(true);
  const dwell = useRef(0);

  const show = (next: 'open' | 'shut') => {
    setOpened(true);
    setState(next);
  };
  // Shut by hand: the resting mouse does not open it again until it goes and comes back.
  const shut = () => {
    armed.current = false;
    clearTimeout(dwell.current);
    dwell.current = 0;
    show('shut');
  };

  useEffect(() => {
    // React is here: the layout's first script keeps js, so the pictures wait for their moment.
    document.documentElement.dataset.live = '';
    setReady(true);
    const open = setTimeout(() => setOpened(true), 400);
    return () => {
      clearTimeout(open);
      clearTimeout(dwell.current);
    };
  }, []);

  useEffect(() => {
    if (state !== 'open') return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && (inside.current || document.activeElement === button.current)) shut();
    };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, [state]);

  const track = (e: React.PointerEvent<HTMLElement>, gone = false) => {
    // Not before the first opening: until then the panel is drawn shut whatever the state says.
    if (e.pointerType !== 'mouse' || !opened) return;
    const over = (el: Element | null) => {
      const box = el?.getBoundingClientRect();
      return !!box && e.clientX >= box.left && e.clientX < box.right && e.clientY >= box.top && e.clientY < box.bottom;
    };
    const onBar = !gone && over(button.current);
    const now = onBar || (!gone && state === 'open' && over(e.currentTarget.querySelector('.panel')));
    if (!onBar) {
      clearTimeout(dwell.current);
      dwell.current = 0;
      armed.current = true;
    }
    if (state === 'open' && inside.current && !now) show('shut');
    inside.current = now;
    if (state === 'shut' && onBar && armed.current && !dwell.current) {
      dwell.current = window.setTimeout(() => {
        dwell.current = 0;
        show('open');
      }, DWELL);
    }
  };

  return (
    <figure
      className="screen"
      data-state={state}
      data-opened={opened ? '' : undefined}
      onPointerMove={(e) => track(e)}
      onPointerLeave={(e) => track(e, true)}
    >
      <span role="img" aria-label={TOLD[state]} />
      <div aria-hidden="true">{children}</div>
      <button
        ref={button}
        className="bar-hit"
        type="button"
        aria-expanded={state === 'open'}
        aria-label="The notch: the AgentValley panel"
        hidden={!ready}
        onClick={() => (state === 'open' ? shut() : show('open'))}
      />
    </figure>
  );
}
