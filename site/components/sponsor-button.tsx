import { Mug } from '@/components/mascot';
import { Button } from '@/components/ui/button';

// The crew's coffee: GitHub Sponsors, as an outline button with the mug in a black tile.
export function SponsorButton() {
  return (
    <Button asChild variant="outline" className="h-11 gap-2.5 rounded-lg bg-background px-4 font-mono text-sm text-foreground no-underline hover:bg-card">
      <a href="https://github.com/sponsors/morsechimwai"><span className="grid size-7 place-items-center rounded-md bg-ink"><Mug /></span>Sponsor the crew</a>
    </Button>
  );
}
