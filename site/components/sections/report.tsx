import { Word } from '@/components/word';

// The PDF report's first page, as the app prints it from a made-up September: one frame of the
// report motion, the camera on the page's head (testing/site.sh report).
export function Report() {
  return (
    <section className="wrap section split report [--cols:minmax(0,4fr)_minmax(0,7fr)]">
      <div className="stack">
        <h2>Hand the month over as a PDF.</h2>
        <p className="lead">
          Export <Word id="pdf"><abbr title="Portable Document Format">PDF</abbr></Word> writes a <Word id="statement">statement of work</Word>: every project for you, or one project for your team or a client.
        </p>
      </div>
      <div className="grid min-w-0 gap-3">
        <img
          className="r-sheet"
          src="/report-sheet.webp"
          width={1500}
          height={1005}
          alt="The first page of a statement of work for September 2026, all projects: $1,414.66 at API prices, a bar for each day, who did the work and what each model cost."
          loading="lazy"
          decoding="async"
        />
        <p className="font-mono text-sm text-muted-foreground">The numbers are made up.</p>
      </div>
    </section>
  );
}
