import { Badge } from '@/components/ui/badge';

// Bits of the app drifting by the hero's heading, as things lie about on a desk: each says only
// what the page already says, never gets in the way, and is never read aloud. Two only, so the
// heading and Download stay the loudest things in the first screen.
export function FloatingBits() {
  return (
    <div className="floating" aria-hidden="true">
      <Badge className="float-need bg-ink font-app text-[.8125rem] font-semibold text-[var(--red-text)]" style={{ top: '62%', left: '4%', '--r': '-4deg', animationDelay: '-2.5s' } as React.CSSProperties}>
        needs you
      </Badge>
      <Badge variant="outline" className="float-chip bg-background font-mono text-[.8125rem] font-normal" style={{ bottom: '4%', right: '14%', '--r': '3deg', animationDelay: '-1s', animationDuration: '8s' } as React.CSSProperties}>
        Sonnet 5.5
      </Badge>
    </div>
  );
}
