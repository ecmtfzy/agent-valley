import { HistoryPanel } from '@/components/history-panel';
import { Word } from '@/components/word';

export function Costs() {
  return (
    <section className="wrap section split flip costs items-start">
      <div className="stack min-[900px]:sticky min-[900px]:top-24">
        <h2>See what each project cost.</h2>
        <p className="lead">Open it from the chart button at the top of the panel. Pick a day, a week or a month, then go back to any earlier one. Choose a day for its hours, or a project for its sessions.</p>
        <p className="text-muted-foreground">
          At <Word id="api"><abbr title="application programming interface">API</abbr> prices</Word>. Kept on your Mac, even after Claude Code clears its old files.
        </p>
      </div>
      <div className="grid min-w-0 [&>figure]:grid [&>figure]:min-w-0 [&>figure]:gap-3">
        <HistoryPanel />
      </div>
    </section>
  );
}
