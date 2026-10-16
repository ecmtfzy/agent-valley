import { StillToggle } from '@/components/still-toggle';
import { Button } from '@/components/ui/button';

// The crew and the name in plain type; the block-letter logo signs off at the foot.
export function Nav() {
  return (
    <header className="wrap nav">
      <a className="brand" href="/">
        <img src="/mark.svg" alt="" width="32" height="26" />
        AgentValley
      </a>
      <nav aria-label="Main">
        {/* Words on this page is reached from every dotted word. A phone keeps the bar to one row: GitHub is in the hero and at the foot. */}
        <a className="max-[479px]:hidden" href="https://github.com/morsechimwai/agent-valley" aria-label="AgentValley on GitHub">GitHub</a>
        <StillToggle />
        <Button asChild className="to-install h-11 rounded-lg border-0 px-3.5 font-mono text-primary-foreground hover:bg-primary/85 hover:text-primary-foreground min-[400px]:px-4">
          <a href="#install">Install</a>
        </Button>
      </nav>
    </header>
  );
}
