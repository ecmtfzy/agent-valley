// The needs-you motion plays as the page scrolls: how far its track has passed the top of the
// screen picks the frame. Kept apart from the motion itself so the page's first script carries
// none of Remotion. The track is `screens` screens tall: the report motion's pace, which the
// owner set by feel at 224 frames over eleven screens.
export const SCRUB = { start: 0, end: 175, screens: 9 } as const;

const clamp01 = (n: number) => Math.min(1, Math.max(0, n));

/** How far through the track the screen is: 0 with its top at the top of the screen, 1 with its foot at the foot. */
export function progressOf(top: number, height: number, viewport: number): number {
  return height <= viewport ? 0 : clamp01(-top / (height - viewport));
}

export function frameAt(progress: number): number {
  return Math.round(SCRUB.start + clamp01(progress) * (SCRUB.end - SCRUB.start));
}
