import { cn } from '@/lib/utils';

export type Person = 'guru' | 'walrus' | 'engineer' | 'pearls' | 'coder' | 'afro' | 'beatnik';
type Pose = 'work' | 'wave' | 'quiet' | 'done' | 'still';

// A mascot: the pose, and over it the pose it moves to. Quiet, done and still are one picture.
const FRAMES: Record<Pose, string[]> = {
  work: ['working', 'blink'],
  wave: ['wave0', 'wave1'],
  quiet: ['quiet'],
  done: ['done'],
  still: ['working'],
};

export function Mascot({ who, pose, size, dot, className }: { who: Person; pose: Pose; size?: string; dot?: boolean; className?: string }) {
  return (
    <span
      className={cn('m', (pose === 'work' || pose === 'wave') && pose, className)}
      style={size ? ({ '--s': size } as React.CSSProperties) : undefined}
    >
      {FRAMES[pose].map((frame) => <img key={frame} src={`/mascots/${who}-${frame}.svg`} alt="" loading="lazy" />)}
      {dot && <i className="dot" />}
    </span>
  );
}

// Nothing running: a cup of coffee, steaming.
export function Mug({ className }: { className?: string }) {
  return (
    <span className={cn('m steam', className)}>
      <img src="/mascots/mug-0.svg" alt="" loading="lazy" />
      <img src="/mascots/mug-1.svg" alt="" loading="lazy" />
    </span>
  );
}

// Halloween: a carved pumpkin, its candle flickering on the mug's steam beat; unlit, only carved.
export function Pumpkin({ lit = true, className }: { lit?: boolean; className?: string }) {
  return lit ? (
    <span className={cn('m steam', className)}>
      <img src="/mascots/pumpkin-0.svg" alt="" loading="lazy" />
      <img src="/mascots/pumpkin-1.svg" alt="" loading="lazy" />
    </span>
  ) : (
    <span className={cn('m', className)}>
      <img src="/mascots/pumpkin-off.svg" alt="" loading="lazy" />
    </span>
  );
}
