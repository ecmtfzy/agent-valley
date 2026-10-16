'use client';

import { useEffect, useRef, useState } from 'react';
import { announce } from '@/components/announcer';
import { Icon } from '@/components/icons';
import { historyView, nextPick, type Action, type Bars, type Pick, type Split } from '@/lib/history';

const SPANS = ['Day', 'Week', 'Month'] as const;

// History as the app draws it, on the reader's own calendar. Drawn only once the page runs on the
// reader's machine: built ahead of time it would show the build day's numbers. Without scripts the
// figure stays hidden.
export function HistoryPanel() {
  const hist = useRef<HTMLDivElement>(null);
  const [now, setNow] = useState<Date | null>(null);
  const [pick, setPick] = useState<Pick | null>(null);
  // `want`: the button that keeps the keyboard when the one pressed is gone.
  const refocus = useRef<{ had: string | undefined; want: string } | null>(null);

  useEffect(() => {
    const at = new Date();
    setNow(at);
    setPick({ span: 'Month', anchor: at, project: null, day: null, hour: null });
  }, []);

  useEffect(() => {
    const r = refocus.current;
    const box = hist.current;
    refocus.current = null;
    if (!r?.had || !box) return;
    const find = (selector: string) => box.querySelector<HTMLElement>(selector);
    (find(`[data-k="${r.had}"]:not(:disabled)`) || find(`[data-k="${r.want}"]`) || find('.h-step:not(:disabled)') || box).focus();
  }, [pick]);

  const view = now && pick ? historyView(pick, now) : null;

  function act(action: Action, want: string) {
    if (!now || !pick) return;
    const active = document.activeElement as HTMLElement | null;
    refocus.current = { had: hist.current?.contains(active) ? active?.dataset.k : undefined, want };
    const next = nextPick(pick, action);
    setPick(next);
    announce(historyView(next, now).announce);
  }
  const click = (action: Action) => act(action, action.a === 'project' ? 'up' : `p-${pick?.project}`);

  const bars = (b: Bars) => (
    <>
      {/* The bars are too narrow to aim at, so they are for the pointer alone; the list under them
          offers the same choices, at a size anyone can press and read aloud. */}
      <div className={`h-bars${b.small ? ' hours' : ''}${b.picked !== null ? ' picking' : ''}`} aria-hidden="true">
        {b.list.map((bar) =>
          bar.future ? (
            <span key={bar.key} className="future"><i style={{ height: '2px' }} /></span>
          ) : (
            <span
              key={bar.key}
              data-a={b.kind}
              className={bar.key === b.picked ? 'on' : undefined}
              title={`${bar.label}, ${bar.price}`}
              onClick={() => click({ a: b.kind, v: String(bar.key) })}
            >
              <i style={{ height: bar.height }} />
            </span>
          ),
        )}
      </div>
      <div className="h-axis" aria-hidden="true"><span>{b.list[0].label}</span><span>{b.list[b.list.length - 1].label}</span></div>
      <label className="h-sel">
        <span className="sr">{b.kind === 'day' ? 'Day' : 'Hour'}</span>
        <select
          data-k={`sel-${b.kind}`}
          value={b.picked === null ? '' : String(b.picked)}
          onChange={(e) => act({ a: b.kind, v: e.target.value }, `sel-${b.kind}`)}
        >
          <option value="">{`All of ${b.all}`}</option>
          {b.list.filter((bar) => !bar.future).map((bar) => (
            <option key={bar.key} value={String(bar.key)}>{`${bar.label} · ${bar.price}`}</option>
          ))}
        </select>
      </label>
    </>
  );

  const split = (s: Split | null) =>
    s && (
      <div className="h-split">
        <p aria-hidden="true">{s.parts.map((part, i) => <i key={i} style={{ flex: part.flex, background: part.color }} />)}</p>
        <span>{s.text}</span>
      </div>
    );

  const rows = view && view.rows.list.length > 0 && (
    <>
      <h3 className="h-head">{view.rows.kind}</h3>
      <div className="h-list">
        {view.rows.kind === 'PROJECTS'
          ? view.rows.list.map((r) => (
              <button
                key={r.key}
                type="button"
                data-k={`p-${r.key}`}
                aria-label={`${r.name}, ${r.price}`}
                title="Shows its sessions"
                onClick={() => click({ a: 'project', v: String(r.key) })}
              >
                <b>{r.name}</b>
                <Icon id="right" />
                <span className="v">{r.price}</span>
              </button>
            ))
          : view.rows.list.map((r) => (
              <p key={r.key}><b>{r.name}</b><span className="v">{r.price}</span></p>
            ))}
      </div>
    </>
  );

  return (
    <figure hidden={!view}>
      <div className="hist" role="group" aria-label="The History page" tabIndex={-1} ref={hist}>
        {view && (
          <>
            <div className="h-top">
              {view.project !== null && (
                <button type="button" className="h-back" data-k="up" onClick={() => click({ a: 'up', v: '' })}>
                  <Icon id="back" />All projects
                </button>
              )}
              <div className="h-seg" role="group" aria-label="Span">
                {SPANS.map((s) => (
                  <button key={s} type="button" data-k={`span-${s}`} aria-pressed={s === view.span} onClick={() => click({ a: 'span', v: s })}>
                    {s}
                  </button>
                ))}
              </div>
            </div>
            <div className="h-stretch">
              <button type="button" className="h-step" data-k="earlier" aria-label="Earlier" disabled={!view.canEarlier} onClick={() => click({ a: 'step', v: '-1' })}>
                <Icon id="left" />
              </button>
              <span className="h-title">{view.title}</span>
              <button type="button" className="h-step" data-k="later" aria-label="Later" disabled={!view.canLater} onClick={() => click({ a: 'step', v: '1' })}>
                <Icon id="right" />
              </button>
              <span className="h-total"><b>{view.total}</b><span className="h-small">at API prices</span></span>
            </div>
            {view.project !== null && <div className="h-name">{view.project}</div>}
            {bars(view.bars)}
            {view.hourBars && bars(view.hourBars)}
            {view.quiet && <p className="h-quiet">No token use in this period.</p>}
            {view.project === null ? <>{split(view.models)}{split(view.agents)}{rows}</> : <>{rows}{split(view.models)}{split(view.agents)}</>}
            <p className="h-foot">{view.since}</p>
          </>
        )}
      </div>
      <figcaption className="font-mono text-sm text-muted-foreground">Click around. The numbers are made up.</figcaption>
    </figure>
  );
}
