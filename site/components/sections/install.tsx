import { Face } from '@/components/face';
import { Mascot } from '@/components/mascot';
import { GetIt, OnPhone } from '@/components/sections/hero';
import { Word } from '@/components/word';

// The end: the whole crew waiting, and the install.
export function Install() {
  return (
    <section className="wrap section final text-center" id="install">
      <div className="lineup" aria-hidden="true">
        <Face who="walrus" />
        <Face who="coder" />
        <Face who="engineer" />
        <Mascot who="guru" pose="wave" />
        <Face who="pearls" />
        <Face who="afro" />
        <Face who="beatnik" />
      </div>
      <h2>Put the valley in your notch.</h2>
      <div className="mt-[30px] flex flex-col items-center text-left [&>.command]:w-full">
        <GetIt />
      </div>
      <p className="small mx-auto">Needs macOS 15 or later and Claude Code. Made for MacBooks with a notch.</p>
      <div className="next mx-auto mt-14 max-w-[540px] text-left">
        <h3 className="font-mono text-[1.3125rem] leading-[1.3]">After you download it</h3>
        <ol role="list">
          <li>Open AgentValley.dmg and drag AgentValley into Applications.</li>
          <li>Open it from Applications. macOS asks once if you want to open an app from the internet: choose Open.</li>
          <li>The panel opens once to show where it lives. After that, point at the notch to open it.</li>
        </ol>
        <p className="small">
          Once a day we check for a new version, and we ask before we install it.
        </p>
        <p className="small">
          We moved house in 0.2. On 0.1 from Homebrew? Run <code>brew uninstall --formula <span className="nw">agent-valley</span></code>, then install again as above. Using the plugin? Copy its command from Settings once more, so it finds the new address. Put the crew in your terminal? Run its install command from the Claude Code settings once more too.
        </p>
        <p className="small">
          To remove: first take out what you added yourself. For the plugin, run <code>claude plugin uninstall <span className="nw">notch-answers@agent-valley</span> &amp;&amp; claude plugin marketplace remove <span className="nw">agent-valley</span></code>. For the crew in your terminal, run the command under How to take it out in the app&apos;s Claude Code settings. Then quit the app and move it from Applications to the Bin, or run <code>brew uninstall --cask <span className="nw">agent-valley</span></code>. Your <Word id="history">History</Word> stays in ~/Library/<wbr />Application Support/<wbr />AgentValley until you delete that folder.
        </p>
        <p className="small">
          Stuck? <a href="https://github.com/morsechimwai/agent-valley/issues">Ask on GitHub</a>.
        </p>
        <OnPhone />
      </div>
    </section>
  );
}
