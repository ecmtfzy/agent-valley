import { IdleSections } from '@/components/idle-sections';
import { Also } from '@/components/sections/also';
import { Costs } from '@/components/sections/costs';
import { Credits } from '@/components/sections/credits';
import { Crew } from '@/components/sections/crew';
import { Footer } from '@/components/sections/footer';
import { Hero } from '@/components/sections/hero';
import { Install } from '@/components/sections/install';
import { Nav } from '@/components/sections/nav';
import { NeedsYou } from '@/components/sections/needs-you';
import { Problem } from '@/components/sections/problem';
import { Report } from '@/components/sections/report';
import { Rows } from '@/components/sections/rows';
import { Terminal } from '@/components/sections/terminal';
import { Trust } from '@/components/sections/trust';
import { Words } from '@/components/sections/words';

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Problem />
        <Rows />
        <NeedsYou />
        <Costs />
        <Report />
        <Terminal />
        <Trust />
        <Crew />
        <Also />
        <Install />
        <Words />
        <Credits />
      </main>
      <Footer />
      <IdleSections />
    </>
  );
}
