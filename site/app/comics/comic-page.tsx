import type { Metadata } from 'next';
import { Footer } from '@/components/sections/footer';
import { GetIt, OnPhone } from '@/components/sections/hero';
import { Nav } from '@/components/sections/nav';
import { AUTHOR, FEED, STRIPS, longDate } from './strips';

// One strip's own page: the strip, its words, the story behind it (the page's children), the way
// to the strips either side, and the same in schema.org terms for search engines.
const SITE = 'https://agentvalley.app';
const at = (slug: string) => `${SITE}/comics/${slug}/`;
const find = (slug: string) => STRIPS.findIndex((s) => s.slug === slug);

export const H2 = 'mt-14 mb-4 text-[clamp(1.5rem,3vw,2rem)]';
export const CODE = 'rounded bg-card px-1 font-mono text-[.9em] [overflow-wrap:anywhere]';
export const PRE = 'mt-4 overflow-x-auto rounded-lg border bg-card p-4 font-mono text-sm leading-relaxed whitespace-pre-wrap';

export function comicMetadata(slug: string): Metadata {
  const s = STRIPS[find(slug)];
  return {
    title: s.headline,
    description: s.description,
    alternates: { canonical: at(slug), types: FEED },
    openGraph: {
      type: 'article',
      url: at(slug),
      title: s.headline,
      description: s.description,
      publishedTime: s.date,
      images: [{ url: `${SITE}/comics/${slug}-og.jpg`, width: 1200, height: 630 }],
    },
    twitter: { card: 'summary_large_image' },
  };
}

// The way to the app from the funnies: the same Download and cask as the home page, here where a
// reader from a strip first meets it.
export function GetTheApp({ className = 'mt-14' }: { className?: string }) {
  return (
    <section aria-labelledby="get-the-app" className={`${className} rounded-xl border bg-card p-6`}>
      <h2 id="get-the-app" className="text-[1.375rem] leading-[1.3]">AgentValley is free and open source.</h2>
      <p className="mt-2 mb-5 text-muted-foreground">A small valley of programmers in your notch. Needs macOS 15 or later and Claude Code.</p>
      <GetIt quiet words={false} />
      <OnPhone />
      <p className="mt-2 font-mono text-sm">
        <a className="inline-flex min-h-11 items-center" href="https://github.com/morsechimwai/agent-valley">Read the code on GitHub</a>
      </p>
    </section>
  );
}

export function ComicPage({ slug, children }: { slug: string; children: React.ReactNode }) {
  const i = find(slug);
  const s = STRIPS[i];
  const [prev, next] = [STRIPS[i - 1], STRIPS[i + 1]];
  const ld = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'Article',
        headline: s.headline,
        description: s.description,
        image: [`${SITE}/comics/${slug}-og.jpg`, `${SITE}/comics/${slug}.webp`],
        datePublished: s.date,
        dateModified: s.date,
        author: { '@type': 'Person', ...AUTHOR },
        mainEntityOfPage: at(slug),
        isPartOf: { '@type': 'CollectionPage', '@id': `${SITE}/comics/`, name: 'The Valley Funnies' },
      },
      {
        '@type': 'BreadcrumbList',
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: 'AgentValley', item: `${SITE}/` },
          { '@type': 'ListItem', position: 2, name: 'The Valley Funnies', item: `${SITE}/comics/` },
          { '@type': 'ListItem', position: 3, name: s.title, item: at(slug) },
        ],
      },
    ],
  };
  return (
    <>
      <Nav sub />
      <main className="wrap pb-24">
        <article className="mx-auto max-w-[44rem] pt-10">
          <nav aria-label="Breadcrumb" className="font-mono text-sm text-muted-foreground">
            <a className="inline-flex min-h-11 items-center" href="/comics/">The Valley Funnies</a> · No. {i + 1}
          </nav>
          <h1 className="mt-2">{s.title}</h1>
          <p className="mt-3 font-mono text-sm text-muted-foreground">
            By <a href={AUTHOR.url} rel="author">{AUTHOR.name}</a> · <time dateTime={s.date}>{longDate(s.date)}</time>
          </p>
          <p className="lead mt-5">{s.lead}</p>

          <figure className="mt-10">
            <img
              className="w-full rounded-lg border"
              src={`/comics/${slug}-1024.webp`}
              srcSet={`/comics/${slug}-640.webp 640w, /comics/${slug}-1024.webp 1024w, /comics/${slug}.webp 2048w`}
              sizes="(min-width: 760px) 704px, calc(100vw - 32px)"
              width={2048}
              height={2144}
              fetchPriority="high"
              alt={`Four-panel pixel-art comic starring ${s.starring}. The words are below.`}
            />
            <figcaption className="mt-6">
              <h2 className="font-mono text-base tracking-normal">What they say</h2>
              <ol className="mt-3 space-y-2" role="list">
                {s.panels.map(([label, line]) => (
                  <li key={label} className="grid grid-cols-[4.5rem_1fr] gap-3">
                    <span className="font-mono text-muted-foreground">{label}</span>
                    <span>{line}</span>
                  </li>
                ))}
              </ol>
            </figcaption>
          </figure>

          {children}

          <GetTheApp />

          <nav aria-label="More strips" className="mt-10 grid gap-4 border-t pt-6 font-mono text-sm min-[560px]:grid-cols-2">
            {prev ? (
              <a className="inline-flex min-h-11 flex-col justify-center no-underline" href={`/comics/${prev.slug}/`}>
                <span className="text-muted-foreground">Before: No. {i}</span>
                <span className="underline underline-offset-[3px]">{prev.title}</span>
              </a>
            ) : (
              <a className="inline-flex min-h-11 flex-col justify-center no-underline" href="/comics/">
                <span className="text-muted-foreground">All strips</span>
                <span className="underline underline-offset-[3px]">The Valley Funnies</span>
              </a>
            )}
            <a className="inline-flex min-h-11 flex-col justify-center no-underline min-[560px]:items-end min-[560px]:text-right" href={next ? `/comics/${next.slug}/` : '/comics/'}>
              <span className="text-muted-foreground">{next ? `Next: No. ${i + 2}` : 'All strips'}</span>
              <span className="underline underline-offset-[3px]">{next ? next.title : 'The Valley Funnies'}</span>
            </a>
          </nav>
        </article>
      </main>
      <Footer />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(ld).replace(/</g, '\\u003c') }} />
    </>
  );
}
