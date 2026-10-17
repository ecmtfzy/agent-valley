import type React from 'react';
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from 'remotion';

// The bar beside the notch while three agents work; one asks to push, the bar shows a red 1, the
// pointer opens the panel, Allow once, and the agent goes back to work. The four pictures are
// the app's own panel, drawn by testing/site.sh needs-you. The site plays it round and round:
// it ends on the bar it starts on.
export type NeedsYouMotionProps = { readonly base: string };

const PICTURE = {
  shut: 'shut-working.webp',
  asking: 'shut-asking.webp',
  open: 'open-asking.webp',
  allowed: 'open-allowed.webp',
} as const;
/** What the motion draws from, for the site to have ready before the player covers its still. */
export const PICTURES = Object.values(PICTURE);

const W = 1200;
const BG = '#f3f2ed';
const AMBER = '#ffb000';
const RED = '#f0503c';

const snap = Easing.bezier(0.2, 0, 0, 1);
const swing = Easing.bezier(0.65, 0, 0.35, 1);
const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;
const tween = (f: number, a: number, b: number, from: number, to: number, easing = snap) =>
  interpolate(f, [a, b], [from, to], { ...clamp, easing });

// In frames, at 30 a second: a second and a half to read the request, one to see it allowed.
export const BEATS = {
  ask: [30, 36],
  ring: 32,
  pointIn: [54, 70],
  // The black island grows into the panel, then what is in it comes in; on the way back the other way round.
  grow: [72, 86],
  fill: [80, 92],
  // The camera leaves the bar ahead of the island, and comes back to it behind.
  wide: [64, 82],
  toCard: [100, 114],
  toAllow: [128, 142],
  pressAllow: 146,
  // A cut, as the app redraws the card: any fade shows both cards at once.
  allowed: 152,
  settle: [152, 164],
  pointOut: [180, 194],
  empty: [196, 202],
  shrink: [198, 214],
  narrow: [202, 220],
  end: 240,
} as const;

export const NEEDS_YOU_MOTION = { width: W, height: 900, fps: 30, durationInFrames: BEATS.end + 1 } as const;

// The pictures are 1088 × 840, cut alike from the panel at two pixels to the point, the top of
// the screen at their top edge. Places below are in their pixels; testing/site.sh needs-you
// stops when the app draws the island or the panel's height elsewhere.
const PANEL = { x: (W - 1088) / 2, w: 1088, h: 840 };
const ISLAND = { x: 244, w: 600, h: 76 };
const HEIGHT = { asking: 836, allowed: 742 };
const COUNT = { x: 323, y: 37 };
const NOTCH = { x: 560, y: 52 };
const ALLOW = { x: 222, y: 412, w: 188, h: 46 };
// Below the bottom edge: the pointer comes in from there and leaves the way it came.
const OFF = { x: 760, y: 1000 };
const inFrame = (p: { x: number; y: number }) => ({ x: PANEL.x + p.x, y: p.y });

const Cursor: React.FC<{ x: number; y: number; press: number }> = ({ x, y, press }) => (
  <svg
    width={34}
    height={44}
    viewBox="0 0 17 22"
    style={{ position: 'absolute', left: x - 4, top: y - 2, scale: String(1 - press * 0.18), transformOrigin: '4px 2px', filter: 'drop-shadow(0 2px 3px rgba(0,0,0,.35))' }}
  >
    <path d="M1 1 L1 17 L5 13 L8 20 L11 19 L8 12 L14 12 Z" fill="#fff" stroke="#000" strokeWidth={1.2} strokeLinejoin="round" />
  </svg>
);

const Ring: React.FC<{ x: number; y: number; w: number; h: number; t: number; color: string }> = ({ x, y, w, h, t, color }) => (
  <div
    style={{
      position: 'absolute',
      left: x - w / 2,
      top: y - h / 2,
      width: w,
      height: h,
      borderRadius: Math.min(w, h) / 2,
      border: `4px solid ${color}`,
      opacity: interpolate(t, [0, 0.15, 1], [0, 1, 0], clamp),
      scale: String(interpolate(t, [0, 1], [0.9, 1.25], clamp)),
    }}
  />
);

// A Mac's menu bar, the notch in the middle of it, as the site draws one: pills for the menus.
const MenuBar: React.FC = () => {
  const pill = (left: number, width: number) => (
    <div key={left} style={{ position: 'absolute', left, top: 31, width, height: 14, borderRadius: 7, background: 'rgba(42,33,24,.22)' }} />
  );
  return (
    // A shade darker than the page, so the top of the screen reads as the picture's edge.
    <div style={{ position: 'absolute', inset: '0 0 auto 0', height: ISLAND.h, background: '#e6e2d6', borderBottom: '1px solid rgba(42,33,24,.12)' }}>
      {[pill(40, 22), pill(84, 70), pill(170, 52), pill(238, 60)]}
      {[pill(W - 300, 40), pill(W - 244, 40), pill(W - 188, 70), pill(W - 100, 56)]}
    </div>
  );
};

export const NeedsYouMotion: React.FC<NeedsYouMotionProps> = ({ base }) => {
  const f = useCurrentFrame();
  const file = (name: string) => (base ? base + name : staticFile(name));
  const B = BEATS;
  const there = (a: readonly [number, number], b: readonly [number, number], easing = snap) =>
    interpolate(f, [a[0], a[1], b[0], b[1]], [0, 1, 1, 0], { ...clamp, easing });

  const asking = f < B.shrink[0] ? tween(f, B.ask[0], B.ask[1], 0, 1) : 0;
  const allowed = f >= B.allowed ? 1 : 0;
  const grow = there(B.grow, B.shrink);
  const fill = there(B.fill, B.empty);
  // The shut bar until the island starts to grow, and again once it is back.
  const shut = 1 - Math.min(1, grow * 5);
  const height = HEIGHT.asking + (HEIGHT.allowed - HEIGHT.asking) * tween(f, B.settle[0], B.settle[1], 0, 1);
  const box = {
    left: ISLAND.x * (1 - grow),
    right: (PANEL.w - ISLAND.x - ISLAND.w) * (1 - grow),
    bottom: PANEL.h - ISLAND.h - (height - ISLAND.h) * grow,
    round: 20 + 20 * grow,
  };

  // The camera: on the bar while it is shut, on the whole panel, a little closer while it asks.
  const onBar = 1 - there(B.wide, B.narrow, swing);
  const onCard = there(B.toCard, B.pointOut, swing);
  const zoom = 1 + onBar * 0.7 + onCard * 0.18;
  const focus = onBar > 0 ? { x: W / 2, y: 0 } : { x: W / 2, y: 330 };

  const keys = [B.pointIn[0], B.pointIn[1], B.toAllow[0], B.toAllow[1], B.pointOut[0], B.pointOut[1]];
  const notch = inFrame(NOTCH);
  const allow = inFrame(ALLOW);
  const cx = interpolate(f, keys, [OFF.x, notch.x, notch.x, allow.x, allow.x, OFF.x], { ...clamp, easing: snap });
  const cy = interpolate(f, keys, [OFF.y, notch.y, notch.y, allow.y, allow.y, OFF.y], { ...clamp, easing: snap });
  const press = interpolate(f, [B.pressAllow - 2, B.pressAllow, B.pressAllow + 4], [0, 1, 0], clamp);
  const count = inFrame(COUNT);

  const picture = (name: string, opacity: number) => (
    <Img src={file(name)} style={{ position: 'absolute', left: 0, top: 0, width: PANEL.w, height: PANEL.h, opacity }} />
  );

  return (
    <AbsoluteFill style={{ background: BG }}>
      <AbsoluteFill style={{ transformOrigin: `${focus.x}px ${focus.y}px`, scale: String(zoom) }}>
        <MenuBar />
        <div style={{ position: 'absolute', left: PANEL.x, top: 0, width: PANEL.w, height: PANEL.h }}>
          {grow > 0 && (
            <div
              style={{
                position: 'absolute',
                inset: 0,
                background: '#000',
                clipPath: `inset(0 ${box.right}px ${box.bottom}px ${box.left}px round 0 0 ${box.round}px ${box.round}px)`,
              }}
            >
              {picture(PICTURE.open, fill * (1 - allowed))}
              {picture(PICTURE.allowed, fill * allowed)}
            </div>
          )}
          {/* The red 1 comes in over the bar, which stays whole beneath it. */}
          {shut > 0 && picture(PICTURE.shut, shut)}
          {shut > 0 && asking > 0 && picture(PICTURE.asking, shut * asking)}
        </div>
        <Ring x={count.x} y={count.y} w={56} h={56} t={tween(f, B.ring, B.ring + 14, 0, 1, Easing.linear)} color={RED} />
        <Ring x={allow.x} y={allow.y} w={ALLOW.w + 16} h={ALLOW.h + 16} t={tween(f, B.pressAllow, B.allowed, 0, 1, Easing.linear)} color={AMBER} />
        <Cursor x={cx} y={cy} press={press} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
