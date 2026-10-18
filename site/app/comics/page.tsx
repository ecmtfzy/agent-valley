import type { Metadata } from 'next';
import { Newsreader, UnifrakturMaguntia } from 'next/font/google';
import { Reveal } from '@/components/reveal';
import { Footer } from '@/components/sections/footer';
import { Nav } from '@/components/sections/nav';
import { STRIPS } from './strips';
import './funnies.css';

// An old Sunday paper: a blackletter name, and the rest in Newsreader, a serif drawn for reading
// news on a screen. Next keeps a copy of both with the site, so nothing loads from Google.
const masthead = UnifrakturMaguntia({ subsets: ['latin'], weight: '400', variable: '--font-masthead' });
const news = Newsreader({ subsets: ['latin'], style: ['normal', 'italic'], axes: ['opsz'], variable: '--font-news' });

const PAGE = 'https://agentvalley.app/comics/';
const TITLE = 'The Valley Funnies: comics about Claude Code';
const DESCRIPTION =
  'Four-panel pixel comics about working with Claude Code: permission prompts, weekly limits, typos and sub-agents, drawn with the AgentValley crew.';

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: PAGE },
  openGraph: {
    type: 'website',
    url: PAGE,
    title: TITLE,
    description: DESCRIPTION,
    images: [{ url: 'https://agentvalley.app/comics/lunch-break-og.jpg', width: 1200, height: 630 }],
  },
  twitter: { card: 'summary_large_image' },
};

// The edition is the newest strip's day, spelled the American way, in the Gregorian calendar.
const latest = STRIPS.map((s) => s.date).sort().at(-1)!;
const edition = new Date(`${latest}T00:00:00Z`).toLocaleDateString('en-US', {
  weekday: 'long',
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  timeZone: 'UTC',
});

// For search engines: a collection of the strips, in order, and where it sits on the site.
const LD = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'CollectionPage',
      '@id': PAGE,
      url: PAGE,
      name: 'The Valley Funnies',
      description: DESCRIPTION,
      mainEntity: {
        '@type': 'ItemList',
        itemListElement: STRIPS.map((s, i) => ({ '@type': 'ListItem', position: i + 1, name: s.title, url: `${PAGE}${s.slug}/` })),
      },
    },
    {
      '@type': 'BreadcrumbList',
      itemListElement: [
        { '@type': 'ListItem', position: 1, name: 'AgentValley', item: 'https://agentvalley.app/' },
        { '@type': 'ListItem', position: 2, name: 'The Valley Funnies', item: PAGE },
      ],
    },
  ],
};

export default function Funnies() {
  return (
    <>
      <Nav sub />
      <main className="wrap pt-8 pb-24">
        <div className={`funnies ${masthead.variable} ${news.variable}`}>
          <header>
            <div className="f-top">
              <p className="f-ear"><b>Weather</b>98% of the weekly limit. Clearing Thursday.</p>
              <h1 className="f-name">The Valley Funnies</h1>
              <p className="f-ear"><b>Home delivery</b>To your notch, whenever an agent needs you.</p>
            </div>
            <p className="f-motto">Comics from a small valley of programmers in your notch.</p>
            <p className="f-date">
              <span>Vol. I, No. {STRIPS.length}</span>
              <time dateTime={latest}>{edition}</time>
              <span>Price: free</span>
            </p>
          </header>

          <ol className="f-strips" role="list">
            {STRIPS.map((s, i) => (
              <li key={s.slug}>
                <Reveal>
                  {/* The whole card is the way in: the headline's link stretches over it. */}
                  <article className="f-card" aria-labelledby={s.slug}>
                    <p className="f-kicker">No. {i + 1} · Starring {s.starring}</p>
                    <h2 id={s.slug} className="f-head">
                      <a href={`/comics/${s.slug}/`}>{s.title}</a>
                    </h2>
                    <img
                      className="f-strip"
                      src={`/comics/${s.slug}-1024.webp`}
                      srcSet={`/comics/${s.slug}-1024.webp 1024w, /comics/${s.slug}.webp 2048w`}
                      sizes="(min-width: 1180px) 480px, (min-width: 768px) calc(50vw - 90px), calc(100vw - 66px)"
                      width={2048}
                      height={2144}
                      loading={i < 2 ? 'eager' : 'lazy'}
                      alt={s.alt}
                    />
                    <p className="f-deck">{s.deck}</p>
                    <p className="f-inside">{s.inside}</p>
                  </article>
                </Reveal>
              </li>
            ))}
          </ol>
        </div>
      </main>
      <Footer />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(LD).replace(/</g, '\\u003c') }} />
    </>
  );
}
