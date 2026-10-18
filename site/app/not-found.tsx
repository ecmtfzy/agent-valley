import type { Metadata } from 'next';
import { Footer } from '@/components/sections/footer';
import { Nav } from '@/components/sections/nav';

// A link that leads nowhere, all year, kept out of search engines: the site's own robots line
// says index, so this page says otherwise.
export const metadata: Metadata = {
  title: 'Page not found · AgentValley',
  robots: { index: false, follow: true },
};

export default function NotFound() {
  return (
    <>
      <Nav sub />
      <main className="wrap grid min-h-[60vh] content-center justify-items-start gap-4 py-24">
        <h1>This page is a ghost.</h1>
        <p className="lead">We looked under every desk.</p>
        <a className="inline-flex min-h-11 items-center font-mono" href="/">Back to the valley</a>
      </main>
      <Footer />
    </>
  );
}
