'use client';

import { useEffect, useState } from 'react';

// The picture's words follow it: open, the panel; shut, the bar.
const TOLD = {
  open: 'The top of a MacBook screen. The AgentValley panel is open under the notch: one session needs you, another is working with two sub-agents. Below, the crew stands in the valley.',
  shut: 'The top of a MacBook screen. Beside the notch, a waving programmer and a red 1: an agent needs you. Below, the crew stands in the valley.',
};

// The hero's panel stands open; the bar beside the notch shuts and opens it, by click, tap or
// keyboard. Without scripts the panel stays open and the button stays hidden. With them it waits
// shut for 400 ms and opens once (set-pieces.css), so the reader sees where it comes from; it
// never opens and shuts on its own again.
export function HeroScreen({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<'open' | 'shut'>('open');
  const [ready, setReady] = useState(false);
  const [opened, setOpened] = useState(false);
  useEffect(() => {
    // React is here: the layout's first script keeps js, so the pictures wait for their moment.
    document.documentElement.dataset.live = '';
    setReady(true);
    const open = setTimeout(() => setOpened(true), 400);
    return () => clearTimeout(open);
  }, []);
  return (
    <figure className="screen" data-state={state} data-opened={opened ? '' : undefined}>
      <span role="img" aria-label={TOLD[state]} />
      <div aria-hidden="true">{children}</div>
      <button
        className="bar-hit"
        type="button"
        aria-expanded={state === 'open'}
        aria-label="The notch: the AgentValley panel"
        hidden={!ready}
        onClick={() => {
          setOpened(true);
          setState((s) => (s === 'open' ? 'shut' : 'open'));
        }}
      />
    </figure>
  );
}
