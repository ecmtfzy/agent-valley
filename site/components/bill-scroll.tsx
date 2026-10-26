'use client';

import { useEffect, useRef } from 'react';

// How high up the screen the panel's foot is when the bill is all the way out.
const OUT = 0.6;

// The costs scene, its bill out from behind the History panel as far as the page has scrolled:
// `--t`, on the bill's slot alone so a frame restyles nothing else, is 0 while the panel's foot is
// still under the screen's, 1 once it is up at 60% of the screen, or sooner, where a jump to the
// bill (Export PDF) puts it, and back down the same way. Stopped, with motion reduced, or before
// the panel is drawn, the bill is all the way out. Off the screen the section is idle and nothing
// is worked out. The pen note's arrow is set on the panel's Export PDF link wherever its buttons
// put it.
export function BillScroll({ children }: { children: React.ReactNode }) {
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const scene = box.current!;
    const section = scene.closest('section')!;
    const slot = scene.querySelector<HTMLElement>('.r-slot')!;
    const hist = scene.querySelector('.hist')!;
    const report = scene.querySelector('#report')!;
    const html = document.documentElement;
    const reduce = matchMedia('(prefers-reduced-motion: reduce)');
    let frame = 0;
    const set = (t: number) => {
      slot.style.setProperty('--t', t.toFixed(3));
      if (t >= 1) scene.dataset.out = '1';
      else delete scene.dataset.out;
    };
    const look = () => {
      frame = 0;
      if (section.classList.contains('idle')) return;
      if (hist.closest('figure')?.hidden || reduce.matches || html.classList.contains('still')) return set(1);
      const h = innerHeight;
      const foot = hist.getBoundingClientRect().bottom;
      // Where the foot is with the bill's top at the page's scroll padding, as a jump leaves it,
      // and room to spare: a smooth scroll stops a hair short, and a link straight to #report lands
      // before what loads above it moves the page some 20px.
      const jump = parseFloat(getComputedStyle(html).scrollPaddingTop) + foot - report.getBoundingClientRect().top + 32;
      const end = Math.max(OUT * h, jump || 0);
      set(Math.min(1, Math.max(0, (h - foot) / Math.max(1, h - end))));
    };
    const soon = () => {
      frame ||= requestAnimationFrame(look);
    };
    // The arrow's head (at 56 of its 72) on the middle of the link, measured from the panel's
    // right edge, as the CSS places the note.
    const point = () => {
      const note = scene.querySelector<HTMLElement>('.c-note');
      const link = hist.querySelector('.h-pdf');
      if (!note || !link) return;
      const at = link.getBoundingClientRect();
      if (at.width) note.style.setProperty('--in', `${(hist.getBoundingClientRect().right - at.left - at.width / 2).toFixed(1)}px`);
    };
    // The panel drawn, hidden, or grown without a scroll (a project, a day); its buttons resized
    // by a late font.
    const sized = new ResizeObserver(() => {
      for (const part of hist.querySelectorAll('.h-pdf, .h-seg')) sized.observe(part);
      point();
      soon();
    });
    sized.observe(hist);
    look();
    addEventListener('scroll', soon, { passive: true });
    addEventListener('resize', soon);
    reduce.addEventListener('change', soon);
    // Stop the animations, and the section coming back on the screen.
    const watch = new MutationObserver(soon);
    watch.observe(html, { attributes: true, attributeFilter: ['class'] });
    watch.observe(section, { attributes: true, attributeFilter: ['class'] });
    return () => {
      removeEventListener('scroll', soon);
      removeEventListener('resize', soon);
      reduce.removeEventListener('change', soon);
      watch.disconnect();
      sized.disconnect();
      cancelAnimationFrame(frame);
    };
  }, []);
  return (
    <div className="c-scene" ref={box}>
      {children}
    </div>
  );
}
