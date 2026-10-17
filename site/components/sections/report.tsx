import { ReportScrub } from '@/components/report-scrub';
import { Word } from '@/components/word';

// The PDF report, as a motion drawn from the app (testing/site.sh report). The page carries the
// last frame as a still, which is all a reader without scripts, with Reduce Motion or with the
// animations stopped sees.
export function Report() {
  return (
    <section className="section report">
      <div className="r-track">
        <div className="r-stage wrap split [--cols:minmax(0,4fr)_minmax(0,7fr)]">
          <div className="stack">
            <h2>Hand the month over as a PDF.</h2>
            <p className="lead">
              Export <Word id="pdf"><abbr title="Portable Document Format">PDF</abbr></Word> writes a <Word id="statement">statement of work</Word>: every project for you, or one project for your team or a client.
            </p>
          </div>
          <div className="r-picture grid min-w-0 gap-3">
            <figure
              className="r-figure"
              role="img"
              aria-label="The History page in the notch panel. Export PDF prints a statement of work for every project, then the panel picks shop-web and prints one for that project alone. Each page opens with its total."
            >
              <img className="r-still" src="/report-motion/still.webp" width={1500} height={1125} alt="" loading="lazy" decoding="async" />
              <ReportScrub />
            </figure>
            <p className="font-mono text-sm text-muted-foreground">The numbers are made up.</p>
          </div>
        </div>
      </div>
    </section>
  );
}
