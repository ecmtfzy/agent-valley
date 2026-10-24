import { Body, Container, Head, Html, Img, Link, Preview, Section, Text } from 'react-email';

// The paper every mail is written on: the wordmark top left, the crew on their desk, a card that
// stays paper in dark mode (only the desk around it goes dark), small print under it. Pictures and
// fonts come from agentvalley.app/email (public/email, shown to the preview as templates/static).
// No default export, so React Email does not list this file as a mail of its own.
export const ASSETS = process.env.EMAIL_ASSETS ?? '/static';
export const INK = '#171717';
export const MUTED = '#52514c';
export const ACCENT = '#723a00';
export const PAPER = '#fafaf7';
export const EDGE = '#e3e1d9';
export const SANS = 'Geist, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif';
export const MONO = '"Geist Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace';

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

// Shared looks for the words inside a card.
export const eyebrow = { margin: '28px 0 0', fontFamily: MONO, fontSize: 13, fontWeight: 600, letterSpacing: '0.08em', textTransform: 'uppercase', color: ACCENT } as const;
export const heading = { margin: '8px 0 0', fontFamily: SANS, fontSize: 30, lineHeight: '36px', fontWeight: 600, letterSpacing: '-0.02em', color: INK } as const;
export const words = { margin: '16px 0 0', fontFamily: SANS, fontSize: 17, lineHeight: '27px', color: INK } as const;
export const quiet = { margin: '20px 0 0', fontFamily: SANS, fontSize: 15, lineHeight: '23px', color: MUTED } as const;
export const button = { display: 'inline-block', marginTop: 24, padding: '15px 22px', borderRadius: 8, background: INK, color: PAPER, fontFamily: MONO, fontSize: 16, fontWeight: 600, textDecoration: 'none' } as const;
export const footLink = { color: MUTED, fontFamily: MONO, textDecoration: 'underline' } as const;

// subject is the mail's <title>; the send script reads it from there.
type Props = { preview: string; subject: string; foot: React.ReactNode; children: React.ReactNode };

export function Letter({ preview, subject, foot, children }: Props) {
  return (
    <Html lang="en">
      <Head>
        <meta name="color-scheme" content="light dark" />
        <meta name="supported-color-schemes" content="light dark" />
        <title>{subject}</title>
        <style>{STYLE}</style>
      </Head>
      <Preview useTitleTag={false}>{preview}</Preview>
      <Body className="desk" style={{ margin: 0, padding: '32px 12px', fontFamily: SANS }}>
        <Container style={{ maxWidth: 520, margin: '0 auto' }}>
          <Section style={{ background: PAPER, border: `1px solid ${EDGE}`, borderRadius: 14, padding: '24px 24px 24px' }}>
            <Link href="https://agentvalley.app">
              <Img src={`${ASSETS}/wordmark.png`} width="176" height="24" alt="AgentValley" style={{ display: 'block', imageRendering: 'pixelated' }} />
            </Link>
            <Img src={`${ASSETS}/crew.png`} width="472" height="69" alt="The AgentValley crew, seven pixel programmers in a row" style={{ display: 'block', width: '100%', maxWidth: 472, height: 'auto', marginTop: 28, imageRendering: 'pixelated' }} />
            {children}
          </Section>
          <Text className="foot" style={{ margin: '20px 4px 0', fontFamily: MONO, fontSize: 13, lineHeight: '20px', color: MUTED, textAlign: 'center' }}>
            {foot}
            <br />
            Not affiliated with Anthropic.
          </Text>
        </Container>
      </Body>
    </Html>
  );
}
