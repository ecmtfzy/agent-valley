import { CopyCommand } from '@/components/copy-command';
import { Face } from '@/components/face';
import { Mascot } from '@/components/mascot';
import { OnPhone } from '@/components/sections/hero';
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
      <div className="mt-[30px] text-left [&>.command]:mx-auto">
        <CopyCommand>
          brew install morsechimwai/<wbr />tap/<wbr /><span className="nw">agent-valley</span>
        </CopyCommand>
      </div>
      <p className="small mx-auto">
        Needs macOS 15 or later, <Word id="homebrew">Homebrew</Word>, and Claude Code. Made for MacBooks with a notch.
      </p>
      <p className="small mx-auto">
        No Homebrew yet? Get it at <a href="https://brew.sh" aria-label="Get Homebrew at brew.sh">brew.sh</a>.
      </p>
      <div className="next mx-auto mt-14 max-w-[540px] text-left">
        <h3 className="font-mono text-[1.3125rem] leading-[1.3]">After you paste it</h3>
        <ol role="list">
          <li>Homebrew <Word id="build">builds</Word> the app on your Mac. It takes <Word id="minute">a minute or so</Word>.</li>
          <li className="[&_.command]:mt-2.5">
            Open it:
            <CopyCommand>
              open <span className="nw">&quot;$(brew --prefix)</span>/<wbr />opt/<wbr /><span className="nw">agent-valley</span>/<wbr />AgentValley.app&quot;
            </CopyCommand>
          </li>
          <li>The panel opens once to show where it lives. After that, point at the notch to open it.</li>
        </ol>
        <p className="small">
          To update: <code>brew upgrade morsechimwai/<wbr />tap/<wbr /><span className="nw">agent-valley</span></code>, then quit the app and open it again.
        </p>
        <p className="small">
          To remove: if you installed the plugin, run <code>claude plugin uninstall <span className="nw">notch-answers@agent-valley</span> &amp;&amp; claude plugin marketplace remove <span className="nw">agent-valley</span></code> first. Then <code>brew uninstall <span className="nw">agent-valley</span></code>. Your <Word id="history">History</Word> stays in ~/Library/<wbr />Application Support/<wbr />AgentValley until you delete that folder.
        </p>
        <p className="small">
          Stuck? <a href="https://github.com/morsechimwai/agent-valley/issues">Ask on GitHub</a>.
        </p>
        <OnPhone />
      </div>
    </section>
  );
}
