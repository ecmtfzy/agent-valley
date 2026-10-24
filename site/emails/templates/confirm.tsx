import { Body, Button, Container, Head, Heading, Hr, Html, Img, Link, Preview, Section, Text } from 'react-email';

// The mail that asks for a yes before anyone is on the Get updates list; api/subscribe.py sends it.
// `npm run emails` renders it with the defaults below, {{link}} and {{days}}, which the function
// fills in. The address stays out of the words: it is typed by anyone, and could carry their text. `npm run email` previews it with PreviewProps. Pictures and fonts come from
// agentvalley.app/email (public/email, shown to the preview as templates/static). The card stays
// paper in dark mode; only the desk around it goes dark.
type Props = { link?: string; days?: string };

const ASSETS = process.env.EMAIL_ASSETS ?? '/static';
const INK = '#171717';
const MUTED = '#52514c';
const ACCENT = '#723a00';
const PAPER = '#fafaf7';
const EDGE = '#e3e1d9';
const SANS = 'Geist, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif';
const MONO = '"Geist Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace';

const face = (family: string, weight: number, file: string) =>
  `@font-face { font-family: '${family}'; font-style: normal; font-weight: ${weight}; src: url(${ASSETS}/fonts/${file}.woff2) format('woff2'); }`;

// Fonts by hand: React Email's Font also sets every element's family, which beat the mono parts.
// The desk's colour lives here only: Body copies its inline style onto an inner cell, where no
// dark-mode rule could reach it. Mail apps without web fonts fall back by family.
const STYLE = [
  face('Geist', 400, 'Geist-Regular'),
  face('Geist', 600, 'Geist-SemiBold'),
  face('Geist Mono', 400, 'GeistMono-Regular'),
  face('Geist Mono', 600, 'GeistMono-SemiBold'),
  '.desk { background: #efede6; }',
  '@media (prefers-color-scheme: dark) { .desk { background: #0f0f0e !important; } .foot, .foot a { color: #a8a8ad !important; } }',
].join('\n');

export default function Confirm({ link = '{{link}}', days = '{{days}}' }: Props) {
  return (
    <Html lang="en">
      <Head>
        <meta name="color-scheme" content="light dark" />
        <meta name="supported-color-schemes" content="light dark" />
        <style>{STYLE}</style>
      </Head>
      <Preview>Press yes and we write when a new version is out. Nothing else.</Preview>
      <Body className="desk" style={{ margin: 0, padding: '32px 12px', fontFamily: SANS }}>
        <Container style={{ maxWidth: 520, margin: '0 auto' }}>
          <Section style={{ background: PAPER, border: `1px solid ${EDGE}`, borderRadius: 14, padding: '28px 24px 24px' }}>
            <Img src={`${ASSETS}/crew.png`} width="472" height="69" alt="The AgentValley crew, seven pixel programmers in a row" style={{ display: 'block', width: '100%', maxWidth: 472, height: 'auto', imageRendering: 'pixelated' }} />
            <Text style={{ margin: '28px 0 0', fontFamily: MONO, fontSize: 13, fontWeight: 600, letterSpacing: '0.08em', textTransform: 'uppercase', color: ACCENT }}>Get updates</Text>
            <Heading as="h1" style={{ margin: '8px 0 0', fontFamily: SANS, fontSize: 30, lineHeight: '36px', fontWeight: 600, letterSpacing: '-0.02em', color: INK }}>
              Say yes, and we&apos;ll write.
            </Heading>
            <Text style={{ margin: '16px 0 0', fontFamily: SANS, fontSize: 17, lineHeight: '27px', color: INK }}>
              Someone, hopefully you, asked for AgentValley news at this address. Press the button and we write when a new version is out. Nothing else.
            </Text>
            <Button href={link} style={{ display: 'inline-block', marginTop: 24, padding: '15px 22px', borderRadius: 8, background: INK, color: PAPER, fontFamily: MONO, fontSize: 16, fontWeight: 600, textDecoration: 'none' }}>
              Yes, send me updates
            </Button>
            <Text style={{ margin: '20px 0 0', fontFamily: SANS, fontSize: 15, lineHeight: '23px', color: MUTED }}>
              The link works for {days} days. If it wasn&apos;t you, do nothing: we won&apos;t write again.
            </Text>
            <Hr style={{ margin: '24px 0 18px', border: 'none', borderTop: `1px solid ${EDGE}` }} />
            <Text style={{ margin: 0, fontFamily: MONO, fontSize: 13, lineHeight: '20px', color: MUTED }}>
              Button not working? Paste this into your browser:
            </Text>
            <Link href={link} style={{ display: 'block', marginTop: 6, fontFamily: MONO, fontSize: 13, lineHeight: '20px', color: ACCENT, wordBreak: 'break-all' }}>
              {link}
            </Link>
          </Section>
          <Text className="foot" style={{ margin: '20px 4px 0', fontFamily: MONO, fontSize: 13, lineHeight: '20px', color: MUTED, textAlign: 'center' }}>
            The crew in your notch · <Link href="https://agentvalley.app" style={{ color: MUTED, fontFamily: MONO, textDecoration: 'underline' }}>agentvalley.app</Link>
            <br />
            Not affiliated with Anthropic.
          </Text>
        </Container>
      </Body>
    </Html>
  );
}

Confirm.PreviewProps = {
  link: 'https://agentvalley.app/api/subscribe?e=reader%40example.com&x=1793435580&t=e89a845884e4892668efbe966e903eb8',
  days: '7',
} satisfies Props;
