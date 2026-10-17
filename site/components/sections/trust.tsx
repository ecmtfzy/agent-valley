import { Reveal } from '@/components/reveal';
import { Word } from '@/components/word';

// What it reads, printed on continuous-form paper.
export function Trust() {
  return (
    <section className="wrap section split trust items-start">
      <h2 className="min-[900px]:sticky min-[900px]:top-24">It reads. It doesn&apos;t touch.</h2>
      <Reveal>
        <ul className="paper" role="list">
          <li>Reads ~/.claude/<wbr />projects and ~/.claude/<wbr />sessions, the files Claude Code writes as it works.</li>
          <li>Looks at Claude Code&apos;s <Word id="process">processes</Word> and each project&apos;s <Word id="git">.git</Word> to show which app and branch a session is in.</li>
          <li>Reads your Claude Code login from the <Word id="keychain">Keychain</Word> only when you turn on <Word id="limits">Plan limits</Word>, and sends it only to api.anthropic.com.</li>
          <li>Besides its own settings, it writes only in one folder: ~/Library/<wbr />Application Support/<wbr />AgentValley. Nothing in ~/.claude changes, unless you put the crew in your terminal.</li>
          <li>You start that yourself, with a command from the app&apos;s settings. It sets the status line in ~/.claude/<wbr />settings.json and adds our font to ~/Library/<wbr />Fonts, and from then on the app keeps the font up to date. With Ghostty, it also adds one line to Ghostty&apos;s config. The command that takes the crew out undoes all of it.</li>
          <li>The only <Word id="hook">hook</Word> is the plugin that brings Allow and Deny to the notch, and you install it yourself.</li>
          <li>Never answers for you. Allow happens only when you choose it.</li>
          <li><Word id="open">Open source</Word>. Read every line on GitHub.</li>
        </ul>
      </Reveal>
    </section>
  );
}
