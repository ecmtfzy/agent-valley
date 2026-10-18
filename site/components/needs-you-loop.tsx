'use client';

import type { PlayerRef } from '@remotion/player';
import { useEffect, useRef, useState } from 'react';

type Loaded = {
  Player: typeof import('@remotion/player').Player;
  motion: typeof import('@/motion/needs-you-motion');
};

// Not with Reduce Motion, nor while Stop the animations has put the class still on <html>.
const MAY_MOVE = '(prefers-reduced-motion: no-preference)';

// The needs-you motion over its still, round and round while the section is on the screen.
// Remotion loads only when the section is near and the page may move; if it fails, the still stays.
export function NeedsYouLoop() {
  const player = useRef<PlayerRef>(null);
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const [may, setMay] = useState(false);
  const [inView, setInView] = useState(false);

  useEffect(() => {
    const section = document.querySelector<HTMLElement>('section.needs-you');
    if (!section) return;
    const html = document.documentElement;
    const media = matchMedia(MAY_MOVE);
    let near = false;
    let loading = false;

    // The player and the pictures it draws, all ready before it covers the still.
    const load = () => {
      if (loading) return;
      loading = true;
      Promise.all([import('@remotion/player'), import('@/motion/needs-you-motion')])
        .then(async ([{ Player }, motion]) => {
          const sources = [...motion.PICTURES.map((name) => `/needs-you/${name}`), ...motion.MASCOTS.map((name) => `/mascots/${name}`)];
          await Promise.all(sources.map((src) => Object.assign(new Image(), { src }).decode()));
          setLoaded({ Player, motion });
        })
        .catch(() => {});
    };
    const fit = () => {
      const ok = media.matches && !html.classList.contains('still');
      setMay(ok);
      if (ok && near) load();
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
    sight.observe(section);
    view.observe(section);
    const stillWatch = new MutationObserver(fit);
    stillWatch.observe(html, { attributes: true, attributeFilter: ['class'] });
    media.addEventListener('change', fit);
    return () => {
      sight.disconnect();
      view.disconnect();
      stillWatch.disconnect();
      media.removeEventListener('change', fit);
    };
  }, []);

  if (!loaded || !may) return null;
  const { Player, motion } = loaded;
  return (
    <div className="s-player" inert aria-hidden="true">
      <Player
        ref={player}
        component={motion.NeedsYouMotion}
        compositionWidth={motion.NEEDS_YOU_MOTION.width}
        compositionHeight={motion.NEEDS_YOU_MOTION.height}
        durationInFrames={motion.NEEDS_YOU_MOTION.durationInFrames}
        fps={motion.NEEDS_YOU_MOTION.fps}
        inputProps={{ base: '/needs-you/' }}
        autoPlay={inView}
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
