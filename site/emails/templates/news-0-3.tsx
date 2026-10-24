import { Button, Heading, Link, Text } from 'react-email';
import { ACCENT, Letter, MONO, button, eyebrow, footLink, heading, quiet, words } from '../letter';

// News for the Get updates list: 0.3.0 to 0.3.2, from the release notes. Sent as a Resend broadcast
// (emails/send.mjs), which swaps {{{RESEND_UNSUBSCRIBE_URL}}} for each reader's own way out.
type Props = { unsubscribe?: string };

const SUBJECT = 'We talk now: AgentValley 0.3';
const NEWS: [string, string][] = [
  ['A voice each.', 'When a session needs you, the one of us on that project plays a few notes on their own instrument and says what it’s about: a command to run, a file to edit, a question, a plan. When the work is done you hear that too.'],
  ['Gone fishing.', 'When a plan limit runs out, one of us tells you we’ve gone fishing, or taken the van for the weekly one, and the same one tells you when we’re back.'],
  ['On from the start.', 'Sounds play from the first run. Settings › Sounds has Crew talks, Crew without the talking, or Chimes, and a switch to keep us quiet. We stay quiet while the screen is locked.'],
  ['Easier to read.', 'On each card, what we’re doing reads first. The red count swells from its number and no longer runs over the words beside it.'],
];

export default function News({ unsubscribe = '{{{RESEND_UNSUBSCRIBE_URL}}}' }: Props) {
  return (
    <Letter
      subject={SUBJECT}
      preview="When a session needs you, one of us plays a few notes and says what it's about."
      art={{ src: 'band-0-3.png', width: 472, height: 290, alt: 'Walt with a red bass, Pearl with a typewriter, Sunny with a singing bowl and Norm with a radio' }}
      foot={<>You get this because you said yes at agentvalley.app. <Link href={unsubscribe} style={footLink}>Unsubscribe</Link> in one click.</>}
    >
      <Text style={eyebrow}>AgentValley 0.3.2</Text>
      <Heading as="h1" style={heading}>We talk now.</Heading>
      <Text style={words}>Three versions came out this week, 0.3.0 to 0.3.2. Most of it you hear rather than see.</Text>
      {NEWS.map(([lead, text]) => (
        <Text key={lead} style={words}>
          <span style={{ fontFamily: MONO, fontSize: 15, fontWeight: 600 }}>{lead}</span> {text}
        </Text>
      ))}
      <Button href="https://agentvalley.app/#install" style={button}>
        Get AgentValley for Mac
      </Button>
      <Text style={quiet}>
        Have it already? Once a day it looks on GitHub and asks before it installs anything. With Homebrew:
      </Text>
      <Text style={{ margin: '8px 0 0', padding: '10px 12px', borderRadius: 6, background: '#efede6', fontFamily: MONO, fontSize: 14, lineHeight: '20px', color: '#171717' }}>
        brew upgrade --cask agent-valley
      </Text>
      <Text style={quiet}>
        Free and open source. Every line of the notes is on <Link href="https://github.com/morsechimwai/agent-valley/releases" style={{ color: ACCENT, textDecoration: 'underline' }}>GitHub</Link>.
      </Text>
    </Letter>
  );
}
