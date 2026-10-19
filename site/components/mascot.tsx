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

// What a working agent holds, by its open call, as the app draws it.
export type Thing = 'thinking' | 'reading' | 'typing' | 'running' | 'searching' | 'calling';
// Frames in each thing's strip: one loop, blinks included (SiteMascotsTests.loop).
const LOOP: Record<Thing, number> = { thinking: 24, reading: 8, typing: 8, running: 8, searching: 8, calling: 8 };

export function Mascot({ who, pose, holds, size, dot, className }: { who: Person; pose: Pose; holds?: Thing; size?: string; dot?: boolean; className?: string }) {
  const style = size ? ({ '--s': size } as React.CSSProperties) : undefined;
  // Still: the thing in hand as the terminal draws it.
  if (holds && pose === 'still') {
    return <span className={cn('m', className)} style={style}><img src={`/mascots/${who}-${holds}.svg`} alt="" loading="lazy" /></span>;
  }
  // At work: the thing in hand, moving, for six seconds, then two with it put down, as the app does.
  if (holds && pose === 'work') {
    return (
      <span className={cn('m holds', className)} style={{ ...style, '--n': LOOP[holds] } as React.CSSProperties}>
        <span className="bare"><Mascot who={who} pose="work" /></span>
        <span className="strip"><img src={`/mascots/${who}-${holds}-run.svg`} alt="" loading="lazy" /></span>
      </span>
    );
  }
  return (
    <span
      className={cn('m', (pose === 'work' || pose === 'wave') && pose, className)}
      style={style}
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
