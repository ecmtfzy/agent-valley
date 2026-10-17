'use client';

import type { PlayerRef } from '@remotion/player';
import { useEffect, useRef, useState } from 'react';
import { frameAt, progressOf } from '@/lib/report-scrub';

type Loaded = {
  Player: typeof import('@remotion/player').Player;
  motion: typeof import('@/motion/report-motion');
};

// Where the page may move: not with Reduce Motion, nor on a screen too short to hold the copy
// and the picture at once. Stop the animations is the class still on <html>. The CSS follows
// data-scrub alone, so the track changes only here, where the reader's place is kept.
const MAY_MOVE = '(prefers-reduced-motion: no-preference) and (min-height: 560px)';

// The report motion over its still, played by the scroll: the section's track grows to eleven
// screens and the frame is how far through it the screen is. Remotion loads only when the
// section is near and may move.
export function ReportScrub() {
  const player = useRef<PlayerRef>(null);
  const frame = useRef(0);
  const [loaded, setLoaded] = useState<Loaded | null>(null);

  useEffect(() => {
    const section = document.querySelector<HTMLElement>('section.report');
    const track = section?.querySelector<HTMLElement>('.r-track');
    const figure = section?.querySelector<HTMLElement>('.r-figure');
    if (!section || !track || !figure) return;
    const html = document.documentElement;
    const media = matchMedia(MAY_MOVE);
    // A screen's height that a phone's sliding toolbar leaves alone; it changes when the phone turns.
    const screen = document.createElement('div');
    screen.style.cssText = 'position:absolute;top:0;width:0;height:100svh;visibility:hidden;pointer-events:none';
    section.append(screen);
    let near = false;
    let loading = false;
    let failed = false;
    let asked = 0;

    const seek = () => {
      asked = 0;
      if (!section.hasAttribute('data-scrub')) return;
      const box = track.getBoundingClientRect();
      frame.current = frameAt(progressOf(box.top, box.height, innerHeight));
      figure.dataset.frame = String(frame.current);
      player.current?.seekTo(frame.current);
    };
    const soon = () => {
      asked ||= requestAnimationFrame(seek);
    };
    // The one place the track grows or folds. A reader below it keeps their place; one inside it
    // when it folds is brought back to the section.
    const fit = () => {
      const may = !failed && media.matches && !html.classList.contains('still');
      const height = may ? `${11 * screen.offsetHeight}px` : '';
      if (track.style.height !== height || section.hasAttribute('data-scrub') !== may) {
        const before = track.getBoundingClientRect();
        const y = scrollY;
        section.toggleAttribute('data-scrub', may);
        track.style.height = height;
        const after = track.getBoundingClientRect();
        // From where the reader was: a page that got shorter has already pulled the scroll up.
        if (before.top < 0 && before.bottom <= innerHeight) scrollTo(0, y + after.height - before.height);
        else if (!may && before.top < 0) section.scrollIntoView({ block: 'start' });
      }
      if (!may) return void delete figure.dataset.frame;
      if (near) load();
      seek();
    };
    // The player and the pictures it draws, all ready before it covers the still; if any fails
    // the still stays, at its own height.
    const load = () => {
      if (loading) return;
      loading = true;
      Promise.all([import('@remotion/player'), import('@/motion/report-motion')])
        .then(async ([{ Player }, motion]) => {
          await Promise.all(motion.PICTURES.map((name) => Object.assign(new Image(), { src: `/report-motion/${name}` }).decode()));
          setLoaded({ Player, motion });
        })
        .catch(() => {
          failed = true;
          fit();
        });
    };

    const sight = new IntersectionObserver(
      ([entry]) => {
        near ||= entry.isIntersecting;
        if (near && section.hasAttribute('data-scrub')) load();
      },
      { rootMargin: '100% 0px' },
    );
    sight.observe(section);
    const stillWatch = new MutationObserver(fit);
    stillWatch.observe(html, { attributes: true, attributeFilter: ['class'] });
    media.addEventListener('change', fit);
    addEventListener('scroll', soon, { passive: true });
    addEventListener('resize', fit);
    fit();
    return () => {
      sight.disconnect();
      stillWatch.disconnect();
      media.removeEventListener('change', fit);
      removeEventListener('scroll', soon);
      removeEventListener('resize', fit);
      cancelAnimationFrame(asked);
      screen.remove();
    };
  }, []);

  // Once the player is there, it starts where the scroll already is.
  useEffect(() => {
    if (loaded) player.current?.seekTo(frame.current);
  }, [loaded]);

  if (!loaded) return null;
  const { Player, motion } = loaded;
  return (
    <div className="r-player" inert aria-hidden="true">
      <Player
        ref={player}
        component={motion.ReportMotion}
        compositionWidth={motion.REPORT_MOTION.width}
        compositionHeight={motion.REPORT_MOTION.height}
        durationInFrames={motion.REPORT_MOTION.durationInFrames}
        fps={motion.REPORT_MOTION.fps}
        inputProps={{ loop: false, base: '/report-motion/' }}
        initialFrame={frame.current}
        controls={false}
        clickToPlay={false}
        doubleClickToFullscreen={false}
        spaceKeyToPlayOrPause={false}
        acknowledgeRemotionLicense
        // No sound, so none of the silent data: audio it keeps ready, which the page's policy refuses.
        numberOfSharedAudioTags={0}
        style={{ width: '100%' }}
      />
    </div>
  );
}
