import { HistoryPanel } from '@/components/history-panel';
import { HuntPumpkin } from '@/components/hunt';
import { Word } from '@/components/word';

// History and its PDF in one section: the panel on the wide side, both stories on the other.
// On a phone they read in order: the cost, the panel, then the PDF.
export function Costs() {
  return (
    <section className="wrap section split flip costs items-start min-[900px]:[grid-template-areas:'panel_text'_'panel_pdf'] min-[900px]:grid-rows-[auto_1fr] min-[900px]:gap-y-14">
      <div className="stack min-[900px]:[grid-area:text]">
        <h2>See what each project cost.</h2>
        <p className="lead">Open History from the chart button at the top of the panel. Pick a day, a week or a month, then go back to any earlier one. Choose a day for its hours, or a project for its sessions.</p>
        <p className="text-muted-foreground">
          At <Word id="api"><abbr title="application programming interface">API</abbr> prices</Word>. Kept on your Mac, even after Claude Code clears its old files.
        </p>
        <HuntPumpkin n={1} />
      </div>
      <div className="grid min-w-0 min-[900px]:[grid-area:panel] [&>figure]:grid [&>figure]:min-w-0 [&>figure]:gap-3">
        <HistoryPanel />
      </div>
      {/* The PDF report's first page, as the app prints it from a made-up September: one frame of the
          report motion, the camera on the page's head, drawn on nothing (testing/site.sh report). */}
      <div className="report stack min-w-0 min-[900px]:[grid-area:pdf]" id="report">
        <h3 className="text-[1.5rem]">Hand the month over as a PDF.</h3>
        <p>
          Export <Word id="pdf"><abbr title="Portable Document Format">PDF</abbr></Word> writes a <Word id="statement">statement of work</Word>: every project for you, or one project for your team or a client.
        </p>
        <img
          className="r-sheet"
          src="/report-sheet.webp"
          width={1500}
          height={975}
          alt="The first page of a statement of work for September 2026, all projects: $1,414.66 at API prices, a bar for each day, who did the work and what each model cost."
          loading="lazy"
          decoding="async"
        />
      </div>
    </section>
  );
}
