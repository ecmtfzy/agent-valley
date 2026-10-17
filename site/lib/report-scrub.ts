// The report motion plays as the page scrolls: how far its track has passed the top of the
// screen picks the frame. Kept apart from the motion itself so the page's first script carries
// none of Remotion.
export const SCRUB = { start: 8, end: 232 } as const;

const clamp01 = (n: number) => Math.min(1, Math.max(0, n));

/** How far through the track the screen is, 0 at its top to 1 at its foot. */
export function progressOf(top: number, height: number, viewport: number): number {
  return height <= viewport ? 0 : clamp01(-top / (height - viewport));
}

export function frameAt(progress: number): number {
  return Math.round(SCRUB.start + clamp01(progress) * (SCRUB.end - SCRUB.start));
}
