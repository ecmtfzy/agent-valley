import { UpdatesForm } from '@/components/updates-form';

// The way back to us after the visit: an email when a new version is out, where we post, and
// GitHub's mail for each release. The phone line (OnPhone) points here, since a phone can only
// take the news for later.
export function Updates() {
  return (
    <div className="next mx-auto mt-14 max-w-[540px] text-left" id="updates">
      <h3 className="font-mono text-[1.3125rem] leading-[1.3]">Get updates</h3>
      <p className="small">Leave your email and we write when a new version is out. Nothing else. Resend keeps the list, and every email has a way out.</p>
      <UpdatesForm />
      <p className="small">
        Or follow us on <a href="https://x.com/morsechimwai">X</a> or <a href="https://bsky.app/profile/morsechimwai.bsky.social">Bluesky</a>, or on <a href="https://github.com/morsechimwai/agent-valley">GitHub</a> choose Watch, then Releases.
      </p>
    </div>
  );
}
