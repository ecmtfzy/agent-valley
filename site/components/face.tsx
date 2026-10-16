import type { Person } from '@/components/mascot';

// A face standing still that waves when a pointer comes by. It loads only when the page reaches it.
export function Face({ who }: { who: Person }) {
  return (
    <span className="face">
      <img src={`/mascots/${who}-working.svg`} alt="" loading="lazy" />
      <img src={`/mascots/${who}-wave0.svg`} alt="" loading="lazy" />
      <img src={`/mascots/${who}-wave1.svg`} alt="" loading="lazy" />
    </span>
  );
}
