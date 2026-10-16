import { Mug } from '@/components/mascot';
import { Badge } from '@/components/ui/badge';

// Bits of the app drifting by the hero's heading, as things lie about on a desk: each says only
// what the page already says, never gets in the way, and is never read aloud.
export function FloatingBits() {
  return (
    <div className="floating" aria-hidden="true">
      <div className="float-term" style={{ top: '6%', right: '0', '--r': '2deg' } as React.CSSProperties}>
        <header><i /><i /><i /></header>
        <pre>{'> Bash npm test\n  112 passed'}</pre>
      </div>
      <Badge className="float-need bg-ink font-app text-[.8125rem] font-semibold text-[var(--red-text)]" style={{ top: '62%', left: '4%', '--r': '-4deg', animationDelay: '-2.5s' } as React.CSSProperties}>
        needs you
      </Badge>
      <span className="float-mug" style={{ top: '0', left: '10%', animationDelay: '-5s', animationDuration: '9s' }}>
        <Mug />
      </span>
      <Badge variant="outline" className="float-chip bg-background font-mono text-[.8125rem] font-normal" style={{ bottom: '4%', right: '14%', '--r': '3deg', animationDelay: '-1s', animationDuration: '8s' } as React.CSSProperties}>
        Sonnet 5.5
      </Badge>
    </div>
  );
}
