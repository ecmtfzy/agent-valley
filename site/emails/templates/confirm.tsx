import { Button, Heading, Hr, Link, Text } from 'react-email';
import { ACCENT, EDGE, Letter, MONO, MUTED, button, eyebrow, footLink, heading, quiet, words } from '../letter';

// The mail that asks for a yes before anyone is on the Get updates list; api/subscribe.py sends it.
// `npm run emails` renders it with the defaults below, {{link}} and {{days}}, which the function
// fills in. The address stays out of the words: it is typed by anyone, and could carry their text.
// `npm run email` previews it with PreviewProps.
type Props = { link?: string; days?: string };

export default function Confirm({ link = '{{link}}', days = '{{days}}' }: Props) {
  return (
    <Letter
      subject="Confirm your AgentValley updates"
      preview="Press yes and we write when a new version is out. Nothing else."
      art={{ src: 'sunny-letter.png', width: 280, height: 290, alt: 'Sunny from the AgentValley crew waves and holds out a sealed envelope' }}
      foot={<>The crew in your notch · <Link href="https://agentvalley.app" style={footLink}>agentvalley.app</Link></>}
    >
      <Text style={eyebrow}>Get updates</Text>
      <Heading as="h1" style={heading}>Say yes, and we&apos;ll write.</Heading>
      <Text style={words}>
        Someone, hopefully you, asked for AgentValley news at this address. Press the button and we write when a new version is out. Nothing else.
      </Text>
      <Button href={link} style={button}>
        Yes, send me updates
      </Button>
      <Text style={quiet}>
        The link works for {days} days. If it wasn&apos;t you, do nothing: we won&apos;t write again.
      </Text>
      <Hr style={{ margin: '24px 0 18px', border: 'none', borderTop: `1px solid ${EDGE}` }} />
      <Text style={{ margin: 0, fontFamily: MONO, fontSize: 13, lineHeight: '20px', color: MUTED }}>
        Button not working? Paste this into your browser:
      </Text>
      <Link href={link} style={{ display: 'block', marginTop: 6, fontFamily: MONO, fontSize: 13, lineHeight: '20px', color: ACCENT, wordBreak: 'break-all' }}>
        {link}
      </Link>
    </Letter>
  );
}

Confirm.PreviewProps = {
  link: 'https://agentvalley.app/api/subscribe?e=reader%40example.com&x=1793435580&t=e89a845884e4892668efbe966e903eb8',
  days: '7',
} satisfies Props;
