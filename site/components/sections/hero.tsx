import { CopyCommand } from '@/components/copy-command';
import { FloatingBits } from '@/components/floating-bits';
import { HeroScreen } from '@/components/hero-screen';
import { Icon } from '@/components/icons';
import { Mascot } from '@/components/mascot';
import { Button } from '@/components/ui/button';
import { TrickOrTreat } from '@/components/trick-or-treat';
import { Word } from '@/components/word';

export function Hero() {
  return (
    <section className="wrap hero grid gap-y-[18px] pt-8 pb-[clamp(64px,12vw,112px)] min-[900px]:grid-cols-2 min-[900px]:items-center min-[900px]:gap-x-14 min-[900px]:gap-y-10 min-[900px]:pt-16 min-[900px]:[grid-template-areas:'head_head'_'copy_screen']">
      <div className="relative min-[900px]:[grid-area:head]">
        <FloatingBits />
        <h1>
          Every agent, at a glance,<br className="hidden min-[900px]:inline" /> right in your notch.
        </h1>
        {/* A badge in the page's own type, not Claude's logo: Anthropic's marks need its written leave. */}
        <p className="mt-5 w-fit rounded-full border border-accent-text/40 bg-card px-3.5 py-1 font-mono text-[.9375rem] font-semibold text-accent-text min-[400px]:text-[1.0625rem]">
          Only for Claude Code, on Mac
        </p>
      </div>
      <div className="min-[900px]:self-start min-[900px]:pt-2 min-[900px]:[grid-area:copy]">
        <p className="max-w-[34em] text-[1.1875rem] leading-[1.55]">
          Each agent, sub-agents too, gets its own row and its own little programmer. See who is working, on which model, and who needs you, without leaving your app.
        </p>
        <div className="mt-8">
          <GetIt quiet>
            <Terms />
          </GetIt>
          <OnPhone />
          <p className="small">
            <a className="inline-flex min-h-11 items-center" href="https://github.com/morsechimwai/agent-valley">View the code on GitHub</a>
          </p>
          {/* Product Hunt's badge, kept here so the page loads nothing from them; no vote count for that reason. */}
          <a className="mt-4 inline-block" href="https://www.producthunt.com/products/agentvalley?embed=true&utm_source=badge-featured&utm_medium=badge&utm_campaign=badge-agentvalley">
            <img src="/product-hunt.svg" alt="Featured on Product Hunt" width="204" height="54" />
          </a>
        </div>
      </div>
      {/* Stacked, the heading and the copy below it are one block; the picture keeps its distance. */}
      <div className="mt-8 min-[900px]:mt-0 min-[900px]:[grid-area:screen]">
        <p className="notch-note" aria-hidden="true">
          The notch. Point at it or press it to open the panel.
          {/* The pen of the row's note on the task (sections/rows.tsx). */}
          <svg viewBox="0 0 72 80">
            <path className="line" d="M3 6 C14 5 27 3 38 7 C50 12 57 30 56.5 47 C56.2 58 56 68 56 77" />
            <path d="M48 66 C51 70 54 74 56 77.5 C58.5 73 61 69 65 65" />
          </svg>
        </p>
        <HeroScreen>
          <ScreenDrawing />
        </HeroScreen>
      </div>
    </section>
  );
}

// The two ways in, in the hero, at the end and under a strip: the dmg of the latest release, or the
// cask. What it costs sits right under Download (children). Quiet: the Copy beside the cask stays
// plain, so Download is the one thing that stands out; only the page's last install lights it amber.
// Off this page there is no Words list for Homebrew to point at (words={false}).
export function GetIt({ quiet = false, words = true, children }: { quiet?: boolean; words?: boolean; children?: React.ReactNode }) {
  return (
    <>
      <Button asChild className="h-12 rounded-lg border-0 px-5 font-mono text-[1.0625rem] font-semibold text-primary-foreground no-underline hover:bg-primary/85 hover:text-primary-foreground">
        <a href="https://github.com/morsechimwai/agent-valley/releases/latest/download/AgentValley.dmg">Download for Mac</a>
      </Button>
      {children}
      <p className="mt-6 mb-2.5 font-mono text-[.9375rem]">
        Or with {words ? <Word id="homebrew">Homebrew</Word> : 'Homebrew'}:
      </p>
      <CopyCommand quiet={quiet}>
        brew install --cask morsechimwai/<wbr />tap/<wbr /><span className="nw">agent-valley</span>
      </CopyCommand>
    </>
  );
}

// What it costs and who checked it, under Download. The end of the page says what it needs on its own line.
export function Terms({ needs = true }: { needs?: boolean }) {
  return (
    <>
      <p className="mt-4 font-mono text-[.9375rem]">
        <strong className="font-semibold text-accent-text">Free</strong> · Open source
        {needs && <> · macOS 15 or later · <span className="nw">For MacBooks with a notch</span></>}
      </p>
      <p className="small">Signed, and Apple checked our papers.</p>
    </>
  );
}

// Shown only on a touch screen without a pointer: the command is for a Mac.
export function OnPhone() {
  return (
    <p className="mt-4 hidden font-mono text-[.9375rem] font-semibold text-accent-text [@media(hover:none)_and_(pointer:coarse)]:block">
      Reading this on a phone? We only fit in a MacBook&apos;s notch. Open this page on your Mac, or <a href="#updates">get updates</a> for later.
    </p>
  );
}

// Halloween night on the wallpaper, under the panel: a moon, three bats, and a spider let down on
// its thread from under the notch, with a note in pen.
function Night() {
  return (
    <div className="night hw" aria-hidden="true">
      <i className="moon" />
      {['b1', 'b2', 'b3'].map((b) => (
        <span key={b} className={`m wave bat ${b}`}>
          <img src="/mascots/bat-0.svg" alt="" fetchPriority="high" />
          <img src="/mascots/bat-1.svg" alt="" fetchPriority="high" />
        </span>
      ))}
      <span className="web">
        <i className="silk" />
        <img className="spider" src="/mascots/spider.svg" alt="" fetchPriority="high" />
      </span>
      <p className="spider-note">He moved in last week. Pays no rent.</p>
    </div>
  );
}

// The top of a MacBook screen: menu bar, the notch with the bar beside it, the panel under it, and
// the crew standing in the valley below.
function ScreenDrawing() {
  return (
    <>
      <div className="menubar" aria-hidden="true">
        <span className="menus"><i /><i /><i /></span>
        <span className="status"><i className="battery" /><span className="clock">Thu 9:41</span></span>
      </div>
      <Night />
      <div className="panel">
        <div className="draw" aria-hidden="true">
        <div className="p-top">
          <span className="p-left">
            <span className="seg"><b>ALL</b>STATUS</span>
            <span className="faces3">
              <img src="/mascots/guru-working.svg" alt="" />
              <img src="/mascots/walrus-working.svg" alt="" />
              <img src="/mascots/afro-working.svg" alt="" />
            </span>
          </span>
          <span className="p-icons"><Icon id="mute" /><Icon id="pin" /><Icon id="chart" /><Icon id="help" /><Icon id="gear" /></span>
        </div>
        <div className="p-head wait-only"><em>1 needs you</em><span className="extra"> · 3 working</span></div>
        <div className="p-head after-only">4 working</div>
        {/* The ALL tab puts each project's line over its cards (0.2.10). */}
        <p className="p-group not-hw">shop-web · 2 sessions</p>
        </div>
        <div className="p-card not-hw" aria-hidden="true">
          <Mascot who="guru" pose="wave" dot />
          <div>
            <p className="p-line">
              <b className="t">Deploy preview build <Icon id="out" /></b>
              <span><em>needs you</em> <span className="model">Sonnet 5.5</span> <Icon id="eyeoff" className="model" /></span>
            </p>
            <p className="p-dim"><Icon id="branch" />preview</p>
            <p>&gt; Bash git push origin preview</p>
            <span className="p-go">Go to Terminal</span>
          </div>
        </div>
        <TrickOrTreat />
        <p className="p-group hw" aria-hidden="true">shop-web · 1 session</p>
        <div className="p-card" aria-hidden="true">
          <Mascot who="walrus" pose="work" holds="reading" />
          <div>
            <p className="p-line"><b className="t">Refactor checkout flow <Icon id="out" /></b><span><span className="tick">3m 16s</span> <span className="model">Opus 5.5</span></span></p>
            <p className="p-dim"><Icon id="branch" />checkout-refactor</p>
            <p>&gt; Read index.tsx</p>
          </div>
          <Mascot who="afro" pose="work" holds="searching" />
          <div>
            <p className="p-line"><b>Map payment call sites</b><span><span className="tick">2m 56s</span> <span className="model">Haiku 5.5</span></span></p>
            <p className="p-line p-dim"><span>&gt; Grep PaymentIntent · 1 step</span><span>Explore</span></p>
          </div>
          <Mascot who="beatnik" pose="work" holds="typing" />
          <div>
            <p className="p-line"><b>Write cart total tests</b><span><span className="tick">1m 08s</span> <span className="model">Sonnet 5.5</span></span></p>
            <p className="p-dim">&gt; Edit cart.test.ts · 4 steps</p>
          </div>
        </div>
        <i className="lights hw" aria-hidden="true"><b /><b /></i>
      </div>
      <div className="bar" aria-hidden="true">
        <span className="wing"><Mascot who="guru" pose="wave" className="wait-only" eager /><Mascot who="guru" pose="work" holds="running" className="after-only" /><span className="count wait-only">1</span></span>
        <span className="lens" />
        <span className="wing"><span className="gauge" /></span>
      </div>
      <div className="valley" aria-hidden="true">
        <Mascot who="guru" pose="wave" eager />
        <Mascot who="walrus" pose="work" holds="reading" eager />
        <Mascot who="afro" pose="work" holds="searching" eager />
        <Mascot who="beatnik" pose="work" holds="typing" eager />
      </div>
    </>
  );
}
