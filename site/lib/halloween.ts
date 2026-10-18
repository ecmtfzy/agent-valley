// Halloween 2026 on the site: from 24 October to the end of 1 November, by the visitor's own clock.
// The layout's first script runs this before the first paint (it is inlined there as text, so it
// must stay one plain function) and marks <html> with halloween; everything else reads that class.
export function isHalloween(now: Date): boolean {
  const month = now.getMonth();
  const day = now.getDate();
  return now.getFullYear() === 2026 && ((month === 9 && day >= 24) || (month === 10 && day === 1));
}
