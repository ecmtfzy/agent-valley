// Sends a rendered mail from out/ to a Resend segment as a broadcast (run `npm run export` first):
//   node send.mjs <mail> <segment>          a draft in Resend, for a last look
//   node send.mjs <mail> <segment> --send   out it goes
// The subject is the mail's <title>. Resend swaps {{{RESEND_UNSUBSCRIBE_URL}}} for each reader's own
// way out and keeps unsubscribed contacts off every broadcast. The key (full access) lives in the
// Mac's Keychain, never in a file: copy it, then
//   security add-generic-password -U -a resend -s agentvalley-resend -w "$(pbpaste)"
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const [mail, segment, go] = process.argv.slice(2);
if (!mail || !segment) throw new Error('usage: node send.mjs <mail> <segment> [--send]');
const key = execFileSync('security', ['find-generic-password', '-s', 'agentvalley-resend', '-w']).toString().trim();

async function resend(path, body) {
  const res = await fetch(`https://api.resend.com${path}`, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: body && JSON.stringify(body),
  });
  const answer = await res.json();
  if (!res.ok) throw new Error(`${path}: ${answer.message ?? res.status}`);
  return answer;
}

const html = readFileSync(new URL(`out/${mail}.html`, import.meta.url), 'utf8');
if (!html.includes('{{{RESEND_UNSUBSCRIBE_URL}}}')) throw new Error(`${mail} has no unsubscribe link`);
const subject = html.match(/<title>([^<]*)<\/title>/)[1]
  .replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const { data } = await resend('/segments');
const to = data.find((s) => s.name === segment);
if (!to) throw new Error(`no segment named ${segment}: ${data.map((s) => s.name).join(', ')}`);

const sent = await resend('/broadcasts', {
  segment_id: to.id,
  from: 'AgentValley <hello@agentvalley.app>',
  reply_to: 'hello@agentvalley.app',
  subject,
  html,
  name: `${mail} to ${segment}`,
  send: go === '--send',
});
console.log(go === '--send' ? `sent: "${subject}" to ${segment}` : `draft: "${subject}" for ${segment}`, `https://resend.com/broadcasts/${sent.id}`);
