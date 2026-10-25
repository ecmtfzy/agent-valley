'use client';

import { MotionLoop } from '@/components/motion-loop';

// The notch gliding between a MacBook and a big display, over its still.
export function DisplayLoop() {
  return (
    <MotionLoop
      section="section.also"
      className="d-player"
      load={async () => {
        const motion = await import('@/motion/display-motion');
        return {
          component: motion.DisplayMotion,
          size: motion.DISPLAY_MOTION,
          inputProps: { base: '/mascots/' },
          pictures: motion.MASCOTS.map((name) => `/mascots/${name}`),
        };
      }}
    />
  );
}
