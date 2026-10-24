'use client';

import { useEffect, useRef } from 'react';

// A picture comes up once as it scrolls into view, from the moment its edge is on the screen. It
// waits hidden only when scripts run (the layout's first script marks <html> with js), so without
// them everything stands from the start.
export function Reveal({ children }: { children: React.ReactNode }) {
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    if (!('IntersectionObserver' in window)) return void el.classList.add('shown');
    const seen = new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) return;
      el.classList.add('shown');
      seen.disconnect();
    });
    seen.observe(el);
    return () => seen.disconnect();
  }, []);
  return <div className="reveal" ref={box}>{children}</div>;
}
