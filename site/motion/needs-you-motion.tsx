import type React from 'react';
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from 'remotion';

// The top of a Mac screen, as the hero draws one: an agent at work in a terminal, the crew in the
// valley below. It asks to push: the terminal waits on it, the bar beside the notch shows a red 1
// and the one who asks waves. The pointer opens the panel over the terminal, presses Allow once,
// the panel shuts and the push goes through. The four pictures of the bar and the panel are the
// app's own, drawn by testing/site.sh needs-you. The site plays it round and round: it ends on
// the empty terminal it starts on.
export type NeedsYouMotionProps = { readonly base: string };

const PICTURE = {
  shut: 'shut-working.webp',
  asking: 'shut-asking.webp',
  open: 'open-asking.webp',
  allowed: 'open-allowed.webp',
} as const;
// The crew in the valley; the first is the one who asks.
const CREW = ['guru', 'walrus', 'afro', 'beatnik'] as const;
const MASCOT = { work: (who: string) => `${who}-working.svg`, wave: (who: string, n: number) => `${who}-wave${n}.svg` };
/** What the motion draws from, for the site to have ready before the player covers its still. */
export const PICTURES = Object.values(PICTURE);
export const MASCOTS = [...CREW.map(MASCOT.work), MASCOT.wave(CREW[0], 0), MASCOT.wave(CREW[0], 1)];

const W = 1200;
const H = 900;
const AMBER = '#ffb000';
const RED = '#f0503c';
// The hero's screen (globals.css): wallpaper, glow, horizon, menu bar, terminal.
const WALL = '#1b110a';
const GLOW = 'rgba(229,160,58,.3)';
const HORIZON = ['#e5a03a', '#d9772e', '#b4501f', '#7a3417', '#3d1f10'];
const MENU = '255,236,210';
const TERM = { bg: '#16120f', head: '#221c17', edge: '#3a322b', fg: '#d9d2c3', dim: '#bab2a2', dot: '#4a4038', wait: '#5a2a26' };
const MONO = 'ui-monospace, "SF Mono", Menlo, monospace';

const snap = Easing.bezier(0.2, 0, 0, 1);
const swing = Easing.bezier(0.65, 0, 0.35, 1);
const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;
const tween = (f: number, a: number, b: number, from: number, to: number, easing = snap) =>
  interpolate(f, [a, b], [from, to], { ...clamp, easing });

// In frames, at 30 a second.
export const BEATS = {
  // The agent's first three lines, then its request.
  lines: [4, 12, 20],
  ask: [28, 32],
  ring: 30,
  pointIn: [44, 58],
  // The black island grows into the panel, then what is in it comes in; on the way back the other way round.
  grow: [60, 74],
  fill: [68, 80],
  toCard: [86, 100],
  toAllow: [112, 126],
  pressAllow: 130,
  // A cut, as the app redraws the card: any fade shows both cards at once.
  allowed: 136,
  settle: [136, 148],
  pointOut: [160, 174],
  empty: [176, 182],
  shrink: [178, 194],
  // The push goes through, and the agent carries on.
  after: [190, 198, 210],
  // The terminal clears for the next round.
  clear: [226, 236],
  end: 240,
} as const;

export const NEEDS_YOU_MOTION = { width: W, height: H, fps: 30, durationInFrames: BEATS.end + 1 } as const;

// The pictures are 1088 × 840, cut alike from the panel at two pixels to the point, the top of
// the screen at their top edge. Places below are in their pixels; testing/site.sh needs-you
// stops when the app draws the island or the panel's height elsewhere.
const PANEL = { x: (W - 1088) / 2, w: 1088, h: 840 };
const ISLAND = { x: 244, w: 600, h: 76 };
const HEIGHT = { asking: 836, allowed: 742 };
const COUNT = { x: 323, y: 37 };
const NOTCH = { x: 560, y: 52 };
const ALLOW = { x: 222, y: 412, w: 188, h: 46 };
const inFrame = (p: { x: number; y: number }) => ({ x: PANEL.x + p.x, y: p.y });
// Where the pointer rests between visits to the notch: on the terminal.
const REST = { x: 760, y: 470 };
const TERMINAL = { x: 150, y: 150, w: 900, h: 420 };

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

// The wallpaper with its glow and the horizon the crew stands on, and the menu bar over it.
const Screen: React.FC = () => {
  const band = 15;
  const pill = (left: number, width: number, round = false) => (
    <div
      key={left}
      style={{ position: 'absolute', left, top: round ? 27 : 32, width, height: round ? 22 : 12, borderRadius: 11, background: `rgba(${MENU},.32)` }}
    />
  );
  return (
    <>
      <AbsoluteFill
        style={{
          background: `radial-gradient(130% 55% at 50% 100%, ${GLOW}, transparent 70%), linear-gradient(180deg, ${WALL} 0 ${H - band * 5}px, ${HORIZON.map(
            (c, i) => `${c} ${H - band * (5 - i)}px ${H - band * (4 - i)}px`,
          ).join(', ')})`,
        }}
      />
      <div style={{ position: 'absolute', inset: '0 0 auto 0', height: ISLAND.h, background: `rgba(${MENU},.09)` }}>
        {[pill(36, 22, true), pill(82, 64), pill(166, 52), pill(238, 60)]}
        <div style={{ position: 'absolute', right: 172, top: 26, width: 46, height: 22, padding: 2, boxSizing: 'border-box', border: `2px solid rgba(${MENU},.6)`, borderRadius: 6 }}>
          <div style={{ width: '70%', height: '100%', borderRadius: 2, background: `rgba(${MENU},.6)` }} />
        </div>
        <div style={{ position: 'absolute', right: 36, top: 22, color: `rgba(${MENU},.8)`, font: `400 24px ${MONO}` }}>Thu 9:41</div>
      </div>
    </>
  );
};

// One line of the terminal, coming in over a few frames from `at`.
const Line: React.FC<{ f: number; at: number; dim?: boolean; children: React.ReactNode }> = ({ f, at, dim, children }) =>
  f < at ? null : (
    <div style={{ color: dim ? TERM.dim : TERM.fg, opacity: tween(f, at, at + 4, 0, 1), whiteSpace: 'pre' }}>{children}</div>
  );

const Terminal: React.FC<{ f: number }> = ({ f }) => {
  const B = BEATS;
  const asking = f >= B.ask[0] && f < B.allowed;
  const done = f >= B.allowed;
  return (
    <div
      style={{
        position: 'absolute',
        left: TERMINAL.x,
        top: TERMINAL.y,
        width: TERMINAL.w,
        height: TERMINAL.h,
        overflow: 'hidden',
        border: `2px solid ${asking ? TERM.wait : TERM.edge}`,
        borderRadius: 20,
        background: TERM.bg,
        boxShadow: '0 44px 80px -36px rgba(0,0,0,.6)',
        font: `400 25px/1.6 ${MONO}`,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, height: 52, padding: '0 22px', background: TERM.head, color: TERM.dim, fontSize: 22 }}>
        {[0, 1, 2].map((i) => <i key={i} style={{ width: 15, height: 15, borderRadius: 8, background: TERM.dot }} />)}
        <span style={{ marginLeft: 14 }}>shop-web</span>
        {asking && <b style={{ marginLeft: 'auto', color: '#ff8a80', fontWeight: 600, opacity: tween(f, B.ask[0], B.ask[1], 0, 1) }}>waiting</b>}
      </div>
      <div style={{ padding: '20px 28px', opacity: 1 - tween(f, B.clear[0], B.clear[1], 0, 1, Easing.linear) }}>
        <Line f={f} at={B.lines[0]}>&gt; Bash npm run build</Line>
        <Line f={f} at={B.lines[1]} dim>{'  Compiled in 4.2s'}</Line>
        <Line f={f} at={B.lines[2]}>&gt; Edit src/deploy/preview.ts</Line>
        {asking && (
          <div style={{ marginTop: 14, padding: '12px 20px', border: `2px solid ${TERM.wait}`, borderRadius: 12, opacity: tween(f, B.ask[0], B.ask[1], 0, 1) }}>
            <div style={{ color: TERM.dim }}>Bash command</div>
            <div style={{ color: TERM.fg }}>{'  git push origin preview'}</div>
            <div style={{ color: TERM.fg }}>Do you want to proceed?</div>
            <div style={{ color: TERM.fg, whiteSpace: 'pre' }}>{'> 1. Yes   2. No'}</div>
          </div>
        )}
        {done && (
          <>
            <Line f={f} at={B.after[0]}>&gt; Bash git push origin preview</Line>
            <Line f={f} at={B.after[1]} dim>{'  preview -> preview'}</Line>
            <Line f={f} at={B.after[2]}>&gt; Read README.md</Line>
          </>
        )}
      </div>
    </div>
  );
};

// The crew on the horizon; the one who asks waves while the request waits.
const Valley: React.FC<{ f: number; file: (name: string) => string }> = ({ f, file }) => {
  const waving = f >= BEATS.ring && f < BEATS.allowed;
  const size = 92;
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, bottom: 62, display: 'flex', justifyContent: 'center', gap: 22 }}>
      {CREW.map((who, i) => (
        <Img
          key={who}
          src={file(i === 0 && waving ? MASCOT.wave(who, Math.floor(f / 6) % 2) : MASCOT.work(who))}
          style={{ width: size, height: size, imageRendering: 'pixelated' }}
        />
      ))}
    </div>
  );
};

export const NeedsYouMotion: React.FC<NeedsYouMotionProps> = ({ base }) => {
  const f = useCurrentFrame();
  // On the site the pictures sit in /needs-you/ and the crew in /mascots/; a render reads both from its public folder.
  const file = (name: string) => (name.endsWith('.svg') ? (base ? `/mascots/${name}` : staticFile(`mascots/${name}`)) : base ? base + name : staticFile(name));
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

  // The camera: the whole screen, a little closer on the card while it asks.
  const onCard = there(B.toCard, B.pointOut, swing);
  const zoom = 1 + onCard * 0.18;

  const keys = [B.pointIn[0], B.pointIn[1], B.toAllow[0], B.toAllow[1], B.pointOut[0], B.pointOut[1]];
  const notch = inFrame(NOTCH);
  const allow = inFrame(ALLOW);
  const cx = interpolate(f, keys, [REST.x, notch.x, notch.x, allow.x, allow.x, REST.x], { ...clamp, easing: snap });
  const cy = interpolate(f, keys, [REST.y, notch.y, notch.y, allow.y, allow.y, REST.y], { ...clamp, easing: snap });
  const press = interpolate(f, [B.pressAllow - 2, B.pressAllow, B.pressAllow + 4], [0, 1, 0], clamp);
  const count = inFrame(COUNT);

  const picture = (name: string, opacity: number) => (
    <Img src={file(name)} style={{ position: 'absolute', left: 0, top: 0, width: PANEL.w, height: PANEL.h, opacity }} />
  );

  return (
    <AbsoluteFill style={{ background: WALL }}>
      <AbsoluteFill style={{ transformOrigin: `${W / 2}px 330px`, scale: String(zoom) }}>
        <Screen />
        <Valley f={f} file={file} />
        <Terminal f={f} />
        <div style={{ position: 'absolute', left: PANEL.x, top: 0, width: PANEL.w, height: PANEL.h }}>
          {grow > 0 && (
            <div
              style={{
                position: 'absolute',
                inset: 0,
                background: '#000',
                clipPath: `inset(0 ${box.right}px ${box.bottom}px ${box.left}px round 0 0 ${box.round}px ${box.round}px)`,
                boxShadow: '0 40px 80px -30px rgba(0,0,0,.7)',
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
