'use client';

import { MotionLoop } from '@/components/motion-loop';

// The needs-you motion over its still: the app's own pictures of the bar and the panel.
export function NeedsYouLoop() {
  return (
    <MotionLoop
      section="section.needs-you"
      className="s-player"
      load={async () => {
        const motion = await import('@/motion/needs-you-motion');
        return {
          component: motion.NeedsYouMotion,
          size: motion.NEEDS_YOU_MOTION,
          inputProps: { base: '/needs-you/' },
          pictures: motion.PICTURES.map((name) => `/needs-you/${name}`),
        };
      }}
    />
  );
}
