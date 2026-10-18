import type { Metadata } from 'next';
import { Footer } from '@/components/sections/footer';
import { Nav } from '@/components/sections/nav';

// A link that leads nowhere, all year, kept out of search engines: the site's own robots line
// says index, so this page says otherwise.
export const metadata: Metadata = {
  title: 'Page not found · AgentValley',
  robots: { index: false, follow: true },
};

const BACK = 'inline-flex min-h-11 items-center font-mono';

// Faye, the Explore agent, any day; the ghost at Halloween (globals.css .hw). On a phone the
// picture comes first, over the words.
export default function NotFound() {
  return (
    <>
      <Nav sub />
      <main className="wrap grid min-h-[60vh] content-center py-24">
        <div className="not-hw grid items-center gap-8 md:grid-cols-[2fr_3fr] md:gap-12">
          <div className="grid justify-items-start gap-4">
            <h1>Faye looked everywhere.</h1>
            <p className="lead">Every folder, twice. No page by that name.</p>
            <a className={BACK} href="/">Back to the valley</a>
          </div>
          <figure className="relative -order-1 m-0 md:order-none">
            <img
              className="block h-auto w-full rounded-[14px]"
              src="/faye-404.webp"
              srcSet="/faye-404-640.webp 640w, /faye-404-1024.webp 1024w, /faye-404.webp 2048w"
              sizes="(min-width: 1180px) 640px, (min-width: 768px) 56vw, calc(100vw - 32px)"
              width={2048}
              height={1530}
              // Lazy, or React preloads her on every page of the site, and on the ghost's.
              loading="lazy"
              alt="Faye, the Explore agent, stands in a desert of printouts holding up an empty folder."
            />
            <span className="tool-tag">Explore · 404 tool uses</span>
          </figure>
        </div>
        <div className="hw grid justify-items-start gap-4">
          <h1>This page is a ghost.</h1>
          <p className="lead">We looked under every desk.</p>
          <a className={BACK} href="/">Back to the valley</a>
        </div>
      </main>
      <Footer />
    </>
  );
}
