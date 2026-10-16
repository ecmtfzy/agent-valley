'use client';

import { useEffect, useId, useRef, useState } from 'react';
import { announce } from '@/components/announcer';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

// Copy: says Copied only once the clipboard took it. Otherwise the command is selected, to copy by
// hand. Without scripts the button stays hidden and the command can still be selected.
export function CopyCommand({ children }: { children: React.ReactNode }) {
  // Three buttons say Copy; each is described by the command it copies.
  const id = useId();
  const code = useRef<HTMLElement>(null);
  const reset = useRef<ReturnType<typeof setTimeout>>(undefined);
  const [ready, setReady] = useState(false);
  const [label, setLabel] = useState('Copy');
  useEffect(() => {
    setReady(true);
    return () => clearTimeout(reset.current);
  }, []);

  async function copy() {
    clearTimeout(reset.current);
    let said = 'Copied';
    try {
      await navigator.clipboard.writeText(code.current!.textContent ?? '');
    } catch {
      getSelection()?.selectAllChildren(code.current!);
      said = /Mac|iPhone|iPad/.test(navigator.platform) ? 'Press ⌘C' : 'Press Ctrl+C';
    }
    setLabel(said);
    announce(said);
    reset.current = setTimeout(() => {
      setLabel('Copy');
      announce('');
    }, 2000);
  }

  return (
    <div className="command">
      <code id={id} ref={code}>{children}</code>
      <Button
        type="button"
        hidden={!ready}
        aria-describedby={id}
        onClick={copy}
        className={cn(
          'copy h-11 min-w-[88px] rounded-lg px-4 font-mono font-semibold active:translate-y-px',
          label === 'Copied' ? 'bg-foreground text-background hover:bg-foreground' : 'bg-amber text-on-amber hover:bg-[var(--amber-hi)]',
        )}
      >
        {label}
      </Button>
    </div>
  );
}
