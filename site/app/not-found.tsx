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

// Words beside a picture of the crew; on a phone the picture comes first.
// A cut-out picture (no backdrop) stands on the page as it is; a scene gets rounded corners.
function Lost({ className, title, lead, art, alt, cutout = false }: { className: string; title: string; lead: string; art: string; alt: string; cutout?: boolean }) {
  return (
    <div className={`${className} grid items-center gap-8 md:grid-cols-[2fr_3fr] md:gap-12`}>
      <div className="grid justify-items-start gap-4">
        <h1>{title}</h1>
        <p className="lead">{lead}</p>
        <a className={BACK} href="/">Back to the valley</a>
      </div>
      <figure className="relative -order-1 m-0 md:order-none">
        <img
          className={`block h-auto w-full ${cutout ? '' : 'rounded-[14px]'}`}
          src={`/${art}.webp`}
          srcSet={`/${art}-640.webp 640w, /${art}-1024.webp 1024w, /${art}.webp 2048w`}
          sizes="(min-width: 1180px) 640px, (min-width: 768px) 56vw, calc(100vw - 32px)"
          width={2048}
          height={1530}
          // Lazy, or React preloads it on every page of the site, and the hidden one here too.
          loading="lazy"
          alt={alt}
        />
        <span className="tool-tag">Explore · 404 tool uses</span>
      </figure>
    </div>
  );
}

// Faye in the desert any day; Pearl in a bedsheet at Halloween (globals.css .hw).
export default function NotFound() {
  return (
    <>
      <Nav sub />
      <main className="wrap grid min-h-[60vh] content-center py-24">
        <Lost
          className="not-hw"
          title="Faye looked everywhere."
          lead="Every folder, twice. No page by that name."
          art="faye-404"
          alt="Faye, the Explore agent, stands in a desert of printouts holding up an empty folder."
        />
        <Lost
          className="hw"
          title="This page is a ghost."
          lead="We looked under every desk."
          art="pearl-ghost-404"
          cutout
          alt="Pearl, in a bedsheet ghost costume with her cat-eye glasses and pearls on top, hides under a desk beside a jack-o'-lantern."
        />
      </main>
      <Footer />
    </>
  );
}
