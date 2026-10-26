'use client';

import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { track } from '@/lib/analytics';

// The email box of Get updates. It posts to api/subscribe.py, which mails a link to confirm; only a
// press on that link's page puts the address in Resend. With scripts the answer shows under the
// box; without them the form posts and the function answers with a small page. `website` is a
// field only a bot fills. Once the mail is out, Sunny pops up holding the letter, as he does in
// the mail itself, and says where to look.
const SAID = {
  sent: "Check your inbox. One click there and you're on the list.",
  full: "We've sent all the mail we can for today. Try again tomorrow.",
  failed: 'That one got away from us. Try again in a minute.',
};
type Said = keyof typeof SAID;

export function UpdatesForm() {
  const [state, setState] = useState<'idle' | 'sending' | Said>('idle');
  const [email, setEmail] = useState('');
  const letter = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (state === 'sent') letter.current?.showModal();
  }, [state]);

  async function send(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setState('sending');
    setEmail(String(new FormData(event.currentTarget).get('email') ?? ''));
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
    <>
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
    {/* A click on the dark round it closes it, as Escape does; the card itself is the div. */}
    <dialog
      ref={letter}
      className="letter"
      aria-labelledby="letter-title"
      onClick={(event) => event.target === event.currentTarget && event.currentTarget.close()}
    >
      <div>
        <img src="/email/sunny-letter.png" width="560" height="580" loading="lazy" alt="Sunny holds out a sealed letter and waves." />
        <p className="eyebrow">Get updates</p>
        <h2 id="letter-title">Check your inbox.</h2>
        <p className="mt-3">
          Sunny is taking a letter to <b className="font-semibold [overflow-wrap:anywhere]">{email}</b>. Press “Yes, send me updates” in it, and we write when a new version is out. Nothing else.
        </p>
        <p className="small">Not there in a few minutes? Look in Spam or Promotions. The link works for 7 days.</p>
        <form method="dialog">
          <Button autoFocus className="mt-6 h-12 rounded-lg px-5 font-mono text-base font-semibold text-primary-foreground hover:bg-primary/85">
            Got it
          </Button>
        </form>
      </div>
    </dialog>
    </>
  );
}
