'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { track } from '@/lib/analytics';

// The email box of Get updates. It posts to api/subscribe.py, which mails a link to confirm; only a
// press on that link's page puts the address in Resend. With scripts the answer shows under the
// box; without them the form posts and the function answers with a small page. `website` is a
// field only a bot fills.
const SAID = {
  sent: "Check your inbox. One click there and you're on the list.",
  full: "We've sent all the mail we can for today. Try again tomorrow.",
  failed: 'That one got away from us. Try again in a minute.',
};
type Said = keyof typeof SAID;

export function UpdatesForm() {
  const [state, setState] = useState<'idle' | 'sending' | Said>('idle');

  async function send(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setState('sending');
    let said: Said = 'failed';
    try {
      const res = await fetch('/api/subscribe', {
        method: 'POST',
        headers: { Accept: 'application/json' },
        body: new URLSearchParams(new FormData(event.currentTarget) as unknown as Record<string, string>),
      });
      const answer = await res.json();
      if (answer.said in SAID) said = answer.said;
    } catch {}
    setState(said);
    if (said === 'sent') track('updates asked');
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
          disabled={state === 'sent'}
          className="h-12 min-w-0 flex-[1_1_14rem] rounded-lg border border-foreground/60 bg-background px-3 font-mono text-base text-foreground"
        />
        <Button
          type="submit"
          disabled={state === 'sending' || state === 'sent'}
          className="h-12 rounded-lg px-5 font-mono text-base font-semibold text-primary-foreground hover:bg-primary/85"
        >
          {state === 'sending' ? 'Sending' : 'Get updates'}
        </Button>
      </div>
      <div className="sr" aria-hidden="true">
        <input name="website" tabIndex={-1} autoComplete="off" />
      </div>
      <p role="status" className="mt-2 min-h-[1.5em] font-mono text-[.9375rem] font-semibold text-accent-text">
        {state === 'idle' || state === 'sending' ? '' : SAID[state]}
      </p>
    </form>
  );
}
