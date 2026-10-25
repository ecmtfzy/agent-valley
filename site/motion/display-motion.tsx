import type React from 'react';
import { AbsoluteFill, Easing, interpolate, spring, staticFile, useCurrentFrame } from 'remotion';
import { Face } from './crew-motion';

// A sign more than a story: a big display with a MacBook in front of it, and the notch, one of us in
// it, gliding from the MacBook to the top of the big display and back. It is ever in one place, as
// the app puts the bar on one display at a time (Settings › General › Display). Round and round.
export type DisplayMotionProps = { readonly base: string; readonly paper?: string };

const W = 720;
const H = 450;
// 60 a second, as the crew's faces count.
const FPS = 60;
const WHO = 'guru';
const HOLDS = 'typing';
/** The crew pictures the motion draws from, for the site to have ready before the player covers its still. */
export const MASCOTS = [`${WHO}-${HOLDS}-run.svg`, `${WHO}-thinking-run.svg`];

// In frames: it leaves the MacBook, leaves the big display, and the round ends where it began.
export const BEATS = { away: 60, back: 270, end: 420 } as const;
const FLIGHT = 64;

export const DISPLAY_MOTION = { width: W, height: H, fps: FPS, durationInFrames: BEATS.end } as const;

const BEZEL = '#0c0c0d';
const EDGE = '#2c2c2e';
const METAL = 'linear-gradient(180deg, #ececee, #c8c8cc)';
const NECK = 'linear-gradient(90deg, #bdbdc2, #ececef 35%, #f4f4f6 55%, #c4c4c8)';
type Screen = { x: number; y: number; w: number; h: number; round: number; bezel: number };
const DISPLAY: Screen = { x: 50, y: 40, w: 420, h: 236, round: 9, bezel: 7 };
const BOOK: Screen = { x: 404, y: 228, w: 280, h: 175, round: 7, bezel: 6 };
const FLOOR = 400;

// The notch: a pill flush with the top of a screen, flaring into it at the shoulders.
const PILL = { w: 100, h: 24, ear: 7 };
const dock = (s: Screen) => ({ x: s.x + s.w / 2, y: s.y });

const ease = Easing.bezier(0.65, 0, 0.35, 1);
const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;

// The desktop picture: a 70s sunset over the valley's horizon (the hero's colours), a cream sky
// so the black notch reads at the top.
const HZ = ['#e5a03a', '#d9772e', '#b4501f', '#7a3417', '#3d1f10'];
const HORIZON = 64;
const BANDS = `linear-gradient(180deg, transparent 0 ${HORIZON}%, ${HZ.map((c, i) => `${c} ${HORIZON + ((100 - HORIZON) / 5) * i}% ${HORIZON + ((100 - HORIZON) / 5) * (i + 1)}%`).join(', ')})`;

const Sunset: React.FC<{ s: Screen }> = ({ s }) => {
  const d = s.w * 0.46;
  return (
    <>
      <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(180deg, #fff6e4 0%, #fde6bf 40%, #f8c98c ${HORIZON}%)` }} />
      <div
        style={{
          position: 'absolute',
          left: (s.w - d) / 2,
          top: (s.h * HORIZON) / 100 - d / 2,
          width: d,
          height: d,
          borderRadius: '50%',
          background: 'linear-gradient(180deg, #ffd166 0%, #f6a53f 30%, #e8792e 50%)',
          // The sun's stripes, thicker as it sets.
          maskImage: 'linear-gradient(180deg, #000 0 27%, transparent 27% 30%, #000 30% 37%, transparent 37% 41%, #000 41% 45%, transparent 45% 50%)',
        }}
      />
      <div style={{ position: 'absolute', inset: 0, background: BANDS }} />
    </>
  );
};

const Glass: React.FC<{ s: Screen }> = ({ s }) => {
  const bar = Math.round(s.h * 0.035);
  const k = s.w / 420;
  const mark = (left: number, width: number, right = false) => (
    <i
      key={left}
      style={{ position: 'absolute', [right ? 'right' : 'left']: left * k, top: bar * 0.3, width: width * k, height: bar * 0.4, borderRadius: 4, background: 'rgba(60,36,14,.35)' }}
    />
  );
  return (
    <div style={{ position: 'absolute', left: s.x, top: s.y, width: s.w, height: s.h, overflow: 'hidden', borderRadius: s.round }}>
      <Sunset s={s} />
      {/* The menu bar: enough to say where the top is. */}
      <div style={{ position: 'absolute', inset: '0 0 auto 0', height: bar, background: 'rgba(255,255,255,.38)' }}>
        {[mark(10, 8), mark(24, 14), mark(44, 14), mark(64, 14), mark(10, 26, true)]}
      </div>
    </div>
  );
};

const Display: React.FC = () => {
  const s = DISPLAY;
  const mid = s.x + s.w / 2;
  const bottom = s.y + s.h + s.bezel;
  return (
    <>
      <div style={{ position: 'absolute', left: mid - 110, top: FLOOR - 12, width: 220, height: 28, borderRadius: '50%', background: 'rgba(0,0,0,.2)', filter: 'blur(10px)' }} />
      <div style={{ position: 'absolute', left: mid - 26, top: bottom - 4, width: 52, height: FLOOR - bottom - 2, background: NECK }} />
      <div style={{ position: 'absolute', left: mid - 82, top: FLOOR - 8, width: 164, height: 8, borderRadius: '3px 3px 4px 4px', background: METAL }} />
      <div
        style={{
          position: 'absolute',
          left: s.x - s.bezel,
          top: s.y - s.bezel,
          width: s.w + s.bezel * 2,
          height: s.h + s.bezel * 2,
          borderRadius: s.round + s.bezel,
          background: BEZEL,
          boxShadow: `inset 0 0 0 1px ${EDGE}, 0 24px 40px -24px rgba(0,0,0,.45)`,
        }}
      />
      <Glass s={s} />
    </>
  );
};

const MacBook: React.FC = () => {
  const s = BOOK;
  const hinge = s.y + s.h + 8;
  return (
    <>
      <div style={{ position: 'absolute', left: s.x - 30, top: hinge + 2, width: s.w + 60, height: 26, borderRadius: '50%', background: 'rgba(0,0,0,.24)', filter: 'blur(9px)' }} />
      <div
        style={{
          position: 'absolute',
          left: s.x - s.bezel,
          top: s.y - s.bezel,
          width: s.w + s.bezel * 2,
          height: s.h + s.bezel + 8,
          borderRadius: `${s.round + s.bezel}px ${s.round + s.bezel}px 3px 3px`,
          background: BEZEL,
          boxShadow: `inset 0 0 0 1px ${EDGE}`,
        }}
      />
      <Glass s={s} />
      <div style={{ position: 'absolute', left: s.x - 26, top: hinge, width: s.w + 52, height: 10, borderRadius: '2px 2px 9px 9px', background: METAL }}>
        <div style={{ position: 'absolute', left: '50%', top: 0, width: 46, height: 4, marginLeft: -23, borderRadius: '0 0 5px 5px', background: '#b9b9be' }} />
      </div>
    </>
  );
};

// The notch at (x, y), its top middle. `docked` 1 is flush with a screen's top, flaring into it;
// 0 is a free pill in the air, rounded all round and a touch bigger.
const Notch: React.FC<{ x: number; y: number; docked: number; scale: number; f: number; file: (name: string) => string }> = ({ x, y, docked, scale, f, file }) => {
  const free = 1 - docked;
  const top = (PILL.h / 2) * free;
  const ear = PILL.ear * docked;
  const flare = (side: 'left' | 'right'): React.CSSProperties => ({
    position: 'absolute',
    top: 0,
    [side]: -ear,
    width: ear,
    height: ear,
    background: `radial-gradient(circle at ${side === 'left' ? '0' : '100%'} 100%, transparent ${ear}px, #000 ${ear + 0.5}px)`,
  });
  return (
    <div
      style={{
        position: 'absolute',
        left: x - PILL.w / 2,
        top: y,
        width: PILL.w,
        height: PILL.h,
        transformOrigin: '50% 0',
        scale: String(scale),
        filter: free > 0.01 ? `drop-shadow(0 ${10 * free}px ${12 * free}px rgba(0,0,0,${0.35 * free}))` : undefined,
      }}
    >
      {ear > 0.2 && <div style={flare('left')} />}
      {ear > 0.2 && <div style={flare('right')} />}
      <div style={{ position: 'absolute', inset: 0, background: '#000', borderRadius: `${top}px ${top}px ${PILL.h / 2}px ${PILL.h / 2}px` }} />
      <div style={{ position: 'absolute', left: 10, top: 4 }}>
        <Face who={WHO} holds={HOLDS} size={16} f={f} file={file} />
      </div>
    </div>
  );
};

// Where the notch is at frame f on a trip that starts at `at`: it lifts off, glides along an arc
// over the top of the big display, and settles with a little give.
const trip = (f: number, at: number, from: { x: number; y: number }, to: { x: number; y: number }) => {
  const t = interpolate(f, [at, at + FLIGHT], [0, 1], { ...clamp, easing: ease });
  const c = { x: (from.x + to.x) / 2 + 80, y: Math.min(from.y, to.y) - 100 };
  const u = 1 - t;
  const x = u * u * from.x + 2 * u * t * c.x + t * t * to.x;
  const y = u * u * from.y + 2 * u * t * c.y + t * t * to.y;
  const landing = at + FLIGHT - 8;
  if (f < landing) {
    const lift = interpolate(f, [at - 6, at + 8], [0, 1], { ...clamp, easing: ease });
    return { x, y, docked: 1 - lift, scale: 1 + 0.08 * lift };
  }
  const settle = spring({ frame: f - landing, fps: FPS, config: { damping: 14, stiffness: 180, mass: 0.8 } });
  return { x, y, docked: Math.min(1, settle), scale: 1 + 0.08 * (1 - settle) };
};

export const DisplayMotion: React.FC<DisplayMotionProps> = ({ base, paper }) => {
  const f = useCurrentFrame();
  // On the site the crew sits in /mascots/; a render reads it from its public folder.
  const file = (name: string) => (base ? base + name : staticFile(`mascots/${name}`));
  const book = dock(BOOK);
  const display = dock(DISPLAY);
  const at = f < BEATS.back - 10 ? trip(f, BEATS.away, book, display) : trip(f, BEATS.back, display, book);
  return (
    <AbsoluteFill style={{ overflow: 'hidden', background: paper }}>
      <Display />
      <MacBook />
      <Notch x={at.x} y={at.y} docked={at.docked} scale={at.scale} f={f} file={file} />
    </AbsoluteFill>
  );
};
