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
export function Mug() {
  return (
    <span className="m steam">
      <img src="/mascots/mug-0.svg" alt="" loading="lazy" />
      <img src="/mascots/mug-1.svg" alt="" loading="lazy" />
    </span>
  );
}
