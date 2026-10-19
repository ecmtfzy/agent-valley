'use client';

import type { PlayerRef } from '@remotion/player';
import { type ComponentType, useEffect, useRef, useState } from 'react';

// What a section's motion brings once loaded: the composition, its size, what it is given, and the
// pictures it draws from.
export type Motion<P extends Record<string, unknown>> = {
  component: ComponentType<P>;
  size: { readonly width: number; readonly height: number; readonly durationInFrames: number; readonly fps: number };
  inputProps: P;
  pictures: string[];
};

type Loaded<P extends Record<string, unknown>> = { Player: typeof import('@remotion/player').Player; motion: Motion<P> };

// Not with Reduce Motion, nor while Stop the animations has put the class still on <html>.
const MAY_MOVE = '(prefers-reduced-motion: no-preference)';

// A section's motion over its still, round and round while the section is on the screen.
// Remotion loads only when the section is near and the page may move; if it fails, the still stays.
export function MotionLoop<P extends Record<string, unknown>>({ section, className, load }: { section: string; className: string; load: () => Promise<Motion<P>> }) {
  const player = useRef<PlayerRef>(null);
  const [loaded, setLoaded] = useState<Loaded<P> | null>(null);
  const [may, setMay] = useState(false);
  const [inView, setInView] = useState(false);

  useEffect(() => {
    const box = document.querySelector<HTMLElement>(section);
    if (!box) return;
    const html = document.documentElement;
    const media = matchMedia(MAY_MOVE);
    let near = false;
    let loading = false;

    // The player and the pictures it draws, all ready before it covers the still.
    const bring = () => {
      if (loading) return;
      loading = true;
      Promise.all([import('@remotion/player'), load()])
        .then(async ([{ Player }, motion]) => {
          await Promise.all(motion.pictures.map((src) => Object.assign(new Image(), { src }).decode()));
          setLoaded({ Player, motion });
        })
        .catch(() => {});
    };
    const fit = () => {
      const ok = media.matches && !html.classList.contains('still');
      setMay(ok);
      if (ok && near) bring();
    };

    const sight = new IntersectionObserver(
      ([entry]) => {
        near ||= entry.isIntersecting;
        fit();
      },
      { rootMargin: '100% 0px' },
    );
    // Off the screen it rests.
    const view = new IntersectionObserver(([entry]) => {
      setInView(entry.isIntersecting);
      if (entry.isIntersecting) player.current?.play();
      else player.current?.pause();
    });
    sight.observe(box);
    view.observe(box);
    const stillWatch = new MutationObserver(fit);
    stillWatch.observe(html, { attributes: true, attributeFilter: ['class'] });
    media.addEventListener('change', fit);
    return () => {
      sight.disconnect();
      view.disconnect();
      stillWatch.disconnect();
      media.removeEventListener('change', fit);
    };
    // The section and its loader are fixed for the page's life.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (!loaded || !may) return null;
  const { Player, motion } = loaded;
  return (
    <div className={className} inert aria-hidden="true">
      <Player
        ref={player}
        component={motion.component}
        compositionWidth={motion.size.width}
        compositionHeight={motion.size.height}
        durationInFrames={motion.size.durationInFrames}
        fps={motion.size.fps}
        inputProps={motion.inputProps}
        autoPlay={inView}
        initiallyMuted
        loop
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
