'use client';

import { MotionLoop } from '@/components/motion-loop';

// Where the tall picture takes over, here and in the still under it (sections/crew.tsx).
export const NARROW = '(max-width: 640px)';

// The crew's org chart over its still, wide or tall to fit the window.
// ponytail: wide or tall is picked once, when it loads; a window turned across 640px keeps the
// first until the page is opened again.
export function CrewLoop() {
  return (
    <MotionLoop
      section="section.crew"
      className="c-player"
      load={async () => {
        const motion = await import('@/motion/crew-motion');
        const tall = matchMedia(NARROW).matches;
        return {
          component: motion.CrewMotion,
          size: tall ? motion.CREW_MOTION_TALL : motion.CREW_MOTION,
          inputProps: { base: '/mascots/', tall },
          pictures: motion.MASCOTS.map((name) => `/mascots/${name}`),
        };
      }}
    />
  );
}
