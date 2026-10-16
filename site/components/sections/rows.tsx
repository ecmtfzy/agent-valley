import { Mascot } from '@/components/mascot';
import { Reveal } from '@/components/reveal';
import { Word } from '@/components/word';

export function Rows() {
  return (
    <section className="wrap section split flip">
      <div className="stack">
        <h2>Every agent gets a row.</h2>
        <p className="lead">
          Sessions get a <Word id="panel">card</Word>. <Word id="sub-agent">Sub-agents</Word> get rows under it. Each row shows the task, the <Word id="model">model</Word> and the latest <Word id="step">step</Word>. Sub-agent rows count their steps too.
        </p>
        <p>Every session in one list, whichever terminal it runs in.</p>
        <p className="text-muted-foreground">No guessed progress bars. If an agent goes <Word id="quiet">quiet</Word>, AgentValley says so.</p>
      </div>
      {/* One row, taken out of the panel and labelled part by part. */}
      <Reveal>
        <figure className="anatomy" role="img" aria-label="One sub-agent row, enlarged and labelled: the task, the time and model, the latest step with the step count, and the agent's type.">
          <div className="draw" aria-hidden="true">
            <p className="callouts"><span>task</span><span>time · model</span></p>
            <div className="row">
              <Mascot who="afro" pose="work" />
              <div>
                <p className="p-line"><b data-part="task">Map payment call sites</b><span data-part="time · model">2m 56s <span className="model">Haiku 5.5</span></span></p>
                <p className="p-line p-dim"><span data-part="latest step · steps so far">&gt; Grep PaymentIntent · 1 step</span><span data-part="type">Explore</span></p>
              </div>
            </div>
            <p className="callouts below"><span>latest step · steps so far</span><span>type</span></p>
          </div>
        </figure>
      </Reveal>
    </section>
  );
}
