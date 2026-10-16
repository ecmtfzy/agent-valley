import { SponsorButton } from '@/components/sponsor-button';
import { Wordmark } from '@/components/wordmark';

// The full logo on the left with the motto under it, the links on the right, and the small print
// under a rule. The crew and the name share one pixel size.
export function Footer() {
  return (
    <footer className="wrap foot border-t pt-12 pb-10 font-mono text-sm text-muted-foreground">
      <div className="flex flex-wrap items-start justify-between gap-x-10 gap-y-6">
        <div>
          <div className="flex items-end gap-3">
            <img className="h-[26px] w-8 flex-none [image-rendering:pixelated] min-[480px]:h-[39px] min-[480px]:w-12" src="/mark.svg" alt="" width="48" height="39" />
            <Wordmark />
          </div>
          <p className="mt-3">A small valley of programmers in your notch.</p>
        </div>
        {/* The page asks for the crew's coffee twice, both after the install: under their photo and here. */}
        <ul className="flex flex-wrap items-center gap-x-6 gap-y-2" role="list">
          <li><a className="inline-flex min-h-11 items-center" href="https://github.com/morsechimwai/agent-valley" aria-label="AgentValley on GitHub">GitHub</a></li>
          <li>
            <SponsorButton />
          </li>
        </ul>
      </div>
      <div className="mt-8 flex flex-wrap justify-between gap-x-6 gap-y-1 border-t pt-5 text-[.8125rem]">
        <p>Made by morsechimwai</p>
        <p>Not affiliated with Anthropic.</p>
      </div>
    </footer>
  );
}
