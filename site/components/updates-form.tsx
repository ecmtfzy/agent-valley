'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { track } from '@/lib/analytics';

// The email box of Get updates. It posts to api/subscribe.py, which keeps the address in Resend.
// With scripts the answer shows under the box; without them the form posts and the function
// answers with a small page. `website` is a field only a bot fills.
const SAID = {
  in: "You're on the list. See you at the next version.",
  failed: 'That one got away from us. Try again in a minute.',
};

export function UpdatesForm() {
  const [state, setState] = useState<'idle' | 'sending' | 'in' | 'failed'>('idle');

  async function send(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setState('sending');
    let ok = false;
    try {
      const res = await fetch('/api/subscribe', {
        method: 'POST',
        headers: { Accept: 'application/json' },
        body: new URLSearchParams(new FormData(event.currentTarget) as unknown as Record<string, string>),
      });
      ok = res.ok && (await res.json()).ok === true;
    } catch {}
    setState(ok ? 'in' : 'failed');
    if (ok) track('updates joined');
  }

  return (
    <form action="/api/subscribe" method="post" onSubmit={send} className="mt-4">
      <label htmlFor="updates-email" className="block font-mono text-[.9375rem]">Your email</label>
      <div className="mt-2 flex flex-wrap gap-2">
        <input
          id="updates-email"
          name="email"
          type="email"
          required
          autoComplete="email"
          maxLength={254}
          disabled={state === 'in'}
          className="h-12 min-w-0 flex-[1_1_14rem] rounded-lg border border-foreground/60 bg-background px-3 font-mono text-base text-foreground"
        />
        <Button
          type="submit"
          disabled={state === 'sending' || state === 'in'}
          className="h-12 rounded-lg px-5 font-mono text-base font-semibold text-primary-foreground hover:bg-primary/85"
        >
          {state === 'sending' ? 'Sending' : 'Get updates'}
        </Button>
      </div>
      <div className="sr" aria-hidden="true">
        <input name="website" tabIndex={-1} autoComplete="off" />
      </div>
      <p role="status" className="mt-2 min-h-[1.5em] font-mono text-[.9375rem] font-semibold text-accent-text">
        {state === 'in' ? SAID.in : state === 'failed' ? SAID.failed : ''}
      </p>
    </form>
  );
}
