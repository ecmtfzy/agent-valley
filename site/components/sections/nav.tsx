import { HalloweenBar } from '@/components/halloween-bar';
import { PumpkinCount } from '@/components/hunt';
import { NavFold } from '@/components/nav-fold';
import { StillToggle } from '@/components/still-toggle';
import { Button } from '@/components/ui/button';
import { Wordmark } from '@/components/wordmark';

// The block-letter name at the very top; down the page the crew in the notch takes its place.
// The link keeps its name either way. `sub`: a page other than the home page, which has no
// animations to stop and sends Install back home.
export function Nav({ sub = false }: { sub?: boolean }) {
  return (
    <>
    <HalloweenBar />
    <header className="wrap nav">
      <a className="brand" href="/" aria-label="AgentValley">
        <img src="/mark.svg" alt="" width="32" height="26" />
        <Wordmark />
      </a>
      <nav aria-label="Main">
        {/* Words on this page is reached from every dotted word. A phone keeps the bar to one row: GitHub is in the hero and at the foot,
            and on the home page Comics is at the foot, since the motion toggle takes its room. */}
        <a className={sub ? undefined : 'max-[559px]:hidden'} href="/comics/">Comics</a>
        <a className="max-[479px]:hidden" href="https://github.com/morsechimwai/agent-valley" aria-label="AgentValley on GitHub">GitHub</a>
        {!sub && <PumpkinCount />}
        {!sub && <StillToggle />}
        <Button asChild className="to-install h-11 rounded-lg border-0 px-3.5 font-mono text-primary-foreground hover:bg-primary/85 hover:text-primary-foreground min-[400px]:px-4">
          <a href={sub ? '/#install' : '#install'}>Install</a>
        </Button>
      </nav>
      <NavFold />
    </header>
    </>
  );
}
