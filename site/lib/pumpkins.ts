// Halloween's pumpkin hunt: which of the five a visitor has lit, kept in their own browser only.
// Blocked storage keeps them for this visit.
export const HUNT = 5;

const lit = new Set<number>();

export function found(): number[] {
  try {
    const saved: unknown = JSON.parse(localStorage.getItem('pumpkins') ?? '[]');
    if (Array.isArray(saved)) for (const n of saved) if (Number.isInteger(n) && n >= 0 && n < HUNT) lit.add(n);
  } catch {}
  return [...lit].sort((a, b) => a - b);
}

export function light(n: number): number[] {
  lit.add(n);
  const all = found();
  try {
    localStorage.setItem('pumpkins', JSON.stringify(all));
  } catch {}
  if (all.length === HUNT) document.documentElement.dataset.pumpkins = 'all';
  dispatchEvent(new Event('pumpkins'));
  return all;
}
