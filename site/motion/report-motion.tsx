import type React from 'react';
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from 'remotion';
import totals from './report-totals.json';

// The History page exports a PDF twice: every project, then shop-web alone. The pictures are the
// app's own, drawn by testing/site.sh report. The site shows one frame, the camera on the first
// page's head; the README's GIF plays it round with `loop`, which fades it in and out.
// Files here import one another by relative paths: Remotion's bundler does not read tsconfig paths.

export const REPORT_MOTION = { width: 1200, height: 900, fps: 30, durationInFrames: 240 } as const;
export type ReportMotionProps = { readonly loop: boolean };

const PICTURE = {
  page: 'history-all.webp',
  projectPage: 'history-shop-web.webp',
  sheetAll: 'report-all.webp',
  sheetProject: 'report-shop-web.webp',
} as const;

const { width: W, height: H } = REPORT_MOTION;
const PAPER = 'rgb(250,247,239)';
const BG = '#f3f2ed';
const AMBER = '#ffb000';

const snap = Easing.bezier(0.2, 0, 0, 1);
const pop = Easing.bezier(0.34, 1.35, 0.64, 1);
const swing = Easing.bezier(0.65, 0, 0.35, 1);
const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;
const tween = (f: number, a: number, b: number, from: number, to: number, easing = snap) =>
  interpolate(f, [a, b], [from, to], { ...clamp, easing });

// In frames; with `loop` it fades in before start and out after end. The count ends before the
// camera moves in, so the zoom shows the PDF's own total.
export const BEATS = {
  start: 8,
  toExport: [8, 22],
  pressExport: 24,
  outA: [26, 40],
  countA: [26, 46],
  zoomA: [48, 62, 86, 98],
  toShopWeb: [98, 112],
  pressShopWeb: 114,
  page: [114, 122],
  toExport2: [120, 132],
  pressExport2: 134,
  outB: [136, 150],
  countB: [136, 154],
  zoomB: [156, 170, 200, 212],
  away: [212, 226],
  end: 232,
  total: REPORT_MOTION.durationInFrames,
} as const;

// The History page as the app draws it (1088 wide), shrunk beside the paper.
const PANEL = { x: 50, y: 188, scale: 0.55 };
const inPanel = (x: number, y: number) => ({ x: PANEL.x + x * PANEL.scale, y: PANEL.y + y * PANEL.scale });
const EXPORT = inPanel(600, 190);
const SHOP_WEB = inPanel(112, 707);
// Below the bottom edge: the cursor comes in from there and leaves the way it came.
const OFF = { x: 900, y: 940 };

// A PDF page at 2.85 pixels to the point, 1696 × 2400, shown 470 wide.
const SHEET_W = 470;
const SHEET_SCALE = SHEET_W / 1696;
// Over the page's total, right on its right edge: wide enough for $1,999.99, short of the
// project's name on the left and the line under it.
const TOTAL = { right: 1564, top: 300, width: 664, height: 96, baseline: 376 };

const money = (n: number) => '$' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

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

const Ring: React.FC<{ x: number; y: number; w: number; h: number; t: number }> = ({ x, y, w, h, t }) => (
  <div
    style={{
      position: 'absolute',
      left: x - w / 2,
      top: y - h / 2,
      width: w,
      height: h,
      borderRadius: 10,
      border: `3px solid ${AMBER}`,
      opacity: interpolate(t, [0, 0.15, 1], [0, 1, 0], clamp),
      scale: String(interpolate(t, [0, 1], [0.92, 1.12], clamp)),
    }}
  />
);

// While it counts, the total is written over the page's own in Geist Mono, the same on every
// computer; once counted the cover goes and the PDF's figure shows.
const Sheet: React.FC<{ src: string; total: number; counting: number | null; style: React.CSSProperties }> = ({ src, total, counting, style }) => (
  <div style={{ position: 'absolute', width: 1696, height: 2400, transformOrigin: '0 0', boxShadow: '0 30px 80px rgba(0,0,0,.28)', ...style }}>
    <Img src={src} style={{ width: 1696, height: 2400, display: 'block' }} />
    {counting !== null && (
      <div
        style={{
          position: 'absolute',
          left: TOTAL.right - TOTAL.width,
          top: TOTAL.top,
          width: TOTAL.width,
          height: TOTAL.height,
          background: PAPER,
          textAlign: 'right',
          fontFamily: '"Geist Mono", ui-monospace, monospace',
          fontWeight: 700,
          fontSize: 75,
          lineHeight: 1,
          color: '#2a2118',
          // The digits sit on the PDF's own baseline.
          paddingTop: TOTAL.baseline - TOTAL.top - 66,
          boxSizing: 'border-box',
        }}
      >
        {money(total * counting)}
      </div>
    )}
  </div>
);

export const ReportMotion: React.FC<ReportMotionProps> = ({ loop }) => {
  const f = useCurrentFrame();
  const B = BEATS;

  const keys = [B.toExport[0], B.toExport[1], B.toShopWeb[0], B.toShopWeb[1], B.toExport2[0], B.toExport2[1], B.away[0], B.away[1]];
  const cx = interpolate(f, keys, [OFF.x, EXPORT.x, EXPORT.x, SHOP_WEB.x, SHOP_WEB.x, EXPORT.x, EXPORT.x, OFF.x], { ...clamp, easing: snap });
  const cy = interpolate(f, keys, [OFF.y, EXPORT.y, EXPORT.y, SHOP_WEB.y, SHOP_WEB.y, EXPORT.y, EXPORT.y, OFF.y], { ...clamp, easing: snap });
  const click = (at: number) => interpolate(f, [at - 2, at, at + 4], [0, 1, 0], clamp);
  const press = Math.max(click(B.pressExport), click(B.pressShopWeb), click(B.pressExport2));
  const ring = (at: number, long = 12) => tween(f, at, at + long, 0, 1, Easing.linear);

  const projectPage = tween(f, B.page[0], B.page[1], 0, 1);

  const outA = tween(f, B.outA[0], B.outA[1], 0, 1, pop);
  const outB = tween(f, B.outB[0], B.outB[1], 0, 1, pop);
  const sheetA = { x: 300 + outA * 390, y: 300 - outA * 190, r: -3 * outA };
  const sheetB = { x: 300 + outB * 412, y: 300 - outB * 162, r: 2.5 * outB };

  const zoomA = interpolate(f, B.zoomA, [0, 1, 1, 0], { ...clamp, easing: swing });
  const zoomB = interpolate(f, B.zoomB, [0, 1, 1, 0], { ...clamp, easing: swing });
  const on = zoomB > 0 ? sheetB : sheetA;
  const focus = { x: on.x + 848 * SHEET_SCALE, y: on.y + 260 * SHEET_SCALE };
  const zoom = Math.max(zoomA, zoomB);

  const count = (span: readonly [number, number]) =>
    f >= span[0] && f < span[1] ? tween(f, span[0], span[1], 0, 1, Easing.out(Easing.cubic)) : null;

  const fade = loop ? interpolate(f, [0, B.start, B.end, B.total], [0, 1, 1, 0], clamp) : 1;
  const sheet = (out: number, at: { x: number; y: number; r: number }): React.CSSProperties => ({
    left: at.x,
    top: at.y,
    scale: String(SHEET_SCALE * (0.6 + 0.4 * out)),
    rotate: `${at.r}deg`,
    opacity: Math.min(1, out * 4),
  });

  return (
    <AbsoluteFill style={{ background: BG }}>
      <AbsoluteFill
        style={{
          opacity: fade,
          transformOrigin: `${focus.x}px ${focus.y}px`,
          scale: String(1 + zoom * 1.35),
          translate: `${zoom * (W / 2 - focus.x)}px ${zoom * (H * 0.42 - focus.y)}px`,
        }}
      >
        <div style={{ position: 'absolute', left: PANEL.x, top: PANEL.y, width: 1088 * PANEL.scale, filter: `brightness(${1 - outA * 0.12 - zoom * 0.5})` }}>
          <Img src={staticFile(PICTURE.page)} style={{ width: '100%', display: 'block', opacity: 1 - projectPage }} />
          <Img src={staticFile(PICTURE.projectPage)} style={{ width: '100%', display: 'block', position: 'absolute', top: 0, opacity: projectPage }} />
        </div>
        <Ring x={EXPORT.x - 4} y={EXPORT.y} w={118} h={38} t={ring(B.pressExport)} />
        <Ring x={SHOP_WEB.x + 30} y={SHOP_WEB.y} w={110} h={34} t={ring(B.pressShopWeb, 7)} />
        <Ring x={EXPORT.x - 4} y={EXPORT.y} w={118} h={38} t={ring(B.pressExport2)} />
        {outA > 0 && <Sheet src={staticFile(PICTURE.sheetAll)} total={totals.all} counting={count(B.countA)} style={sheet(outA, sheetA)} />}
        {outB > 0 && <Sheet src={staticFile(PICTURE.sheetProject)} total={totals['shop-web']} counting={count(B.countB)} style={sheet(outB, sheetB)} />}
        <Cursor x={cx} y={cy} press={press} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
