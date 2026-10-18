// Every crew comic, oldest first. The funnies page, each story page, the sitemap and the edition
// line all read this; a story page adds its own article under the strip.
export type Strip = {
  slug: string;
  title: string;
  date: string;
  starring: string;
  /** On the funnies page: what happens, and what the story page explains. */
  deck: string;
  inside: string;
  /** The picture in words, with everything said in it. */
  alt: string;
  /** The story page's title and summary for search results and shares, and its first paragraph. */
  headline: string;
  description: string;
  lead: string;
  /** What they say, panel by panel: the time or number on the panel, then the words. */
  panels: [string, string][];
};

export const STRIPS: Strip[] = [
  {
    slug: 'lunch-break',
    title: 'Lunch break',
    date: '2026-10-18',
    starring: 'Sunny',
    deck: 'Claude Code asks to run npm install a minute after you leave for lunch, then waits the whole hour for an answer.',
    inside: 'Inside: why it waits, and the fix.',
    alt: 'Four-panel comic. 12:00, Sunny at his desk: “You’re at lunch? I’ll have the refactor done before you’re back.” 12:01, pointing at a dialog on his screen: “First, may I run npm install?” 12:40, he waves by the empty chair. 1:05, still waving: “I switched arms at half past.”',
    headline: 'Lunch break: Claude Code waits for permission while you eat',
    description:
      'A four-panel comic about Claude Code asking to run npm install a minute after you leave for lunch, and how to stop it waiting an hour for you.',
    lead: 'You leave Claude Code with a refactor and go to lunch. A minute later it asks to run a command, and then it waits for you the whole hour.',
    panels: [
      ['12:00', 'Sunny, at the desk: “You’re at lunch? I’ll have the refactor done before you’re back.”'],
      ['12:01', 'Sunny points at a dialog on the screen: “First, may I run npm install?”'],
      ['12:40', 'Sunny stands by the empty chair, waving.'],
      ['1:05', 'Sunny, still waving: “I switched arms at half past.”'],
    ],
  },
  {
    slug: 'last-prompt',
    title: 'Last prompt',
    date: '2026-10-18',
    starring: 'Norm, Sunny and Walt',
    deck: 'Two percent of the weekly limit left, one prompt to spend, and it goes on “fix it”.',
    inside: 'Inside: where to see your limits, and a prompt worth the last two percent.',
    alt: 'Four-panel comic. Tuesday. Norm points at a meter on his screen: “Weekly limit at 98 percent.” Sunny folds his hands: “Last prompt of the week. Let’s make it count.” The screen reads “> fix it”. Norm, Sunny and Walt sit over coffee, and Walt says: “See you Thursday.”',
    headline: 'Last prompt: Claude Code at 98% of the weekly limit',
    description:
      'A four-panel comic about spending the last prompt of the week on “fix it”, and how to watch your Claude Code limits and write a prompt that counts.',
    lead: 'The weekly limit is at 98 percent. There is room for one more prompt, so the crew thinks it over, and sends “fix it”.',
    panels: [
      ['1', 'Tuesday. Norm points at a meter on his screen: “Weekly limit at 98 percent.”'],
      ['2', 'Sunny, hands folded: “Last prompt of the week. Let’s make it count.”'],
      ['3', 'The screen: “> fix it”'],
      ['4', 'Norm, Sunny and Walt over coffee. Walt: “See you Thursday.”'],
    ],
  },
  {
    slug: 'typo-case',
    title: 'The typo case',
    date: '2026-10-18',
    starring: 'Pearl and Judy',
    deck: 'Pearl reads the bill from the last page first: $7.30 to fix “recieve”. Judy has a song about it.',
    inside: 'Inside: what made one typo cost $7.30.',
    alt: 'Four-panel comic. Pearl studies a cost chart through a magnifying glass: “Someone spent $7.30 fixing one typo.” She reads a long printout: “Always start at the last page.” On the desk lies a report titled “Fixing ‘recieve’”. Judy plays a sunburst guitar: “I wrote a song about it too.”',
    headline: 'The typo case: why one small fix cost $7.30 in Claude Code',
    description:
      'A four-panel comic about a Claude Code session that spent $7.30 fixing one typo, and why a small task gets expensive at the end of a long conversation.',
    lead: 'Pearl reads a long session from the last page first. The total: $7.30. The task: one typo.',
    panels: [
      ['1', 'Pearl studies a cost chart through a magnifying glass: “Someone spent $7.30 fixing one typo.”'],
      ['2', 'She reads a long printout, a pile of pages beside her: “Always start at the last page.”'],
      ['3', 'On the desk, the report’s cover: “Fixing ‘recieve’”.'],
      ['4', 'Judy, with a sunburst guitar: “I wrote a song about it too.”'],
    ],
  },
  {
    slug: 'explore',
    title: 'Explore',
    date: '2026-10-18',
    starring: 'Sunny and Faye',
    deck: 'Sunny asks Faye, the Explore agent, for the login button. 214 tool uses later, it is in the file he has open.',
    inside: 'Inside: how to hand Claude Code the right file.',
    alt: 'Four-panel comic. Sunny asks: “Faye, where’s the login button?” Faye walks a desert of printouts, tagged “Explore · 214 tool uses”. She comes back dusty, carrying a stack of paper: “Found it.” Then: “ContentView.swift, line 12.” Sunny points at his screen: “That’s the file I have open.”',
    headline: 'Explore: Claude Code searches the repo for the file you have open',
    description:
      'A four-panel comic about the Explore sub-agent taking 214 tool uses to find a button in the file you already had open, and how to point Claude Code at the right file.',
    lead: 'Sunny asks where the login button is. Faye, the Explore sub-agent, searches the whole repository and comes back with the answer: the file Sunny has open.',
    panels: [
      ['1', 'Sunny at his desk: “Faye, where’s the login button?”'],
      ['2', 'Faye walks a desert of printouts. The tag reads “Explore · 214 tool uses”.'],
      ['3', 'She is back, dusty, carrying a stack of paper: “Found it.”'],
      ['4', 'Faye: “ContentView.swift, line 12.” Sunny points at his screen: “That’s the file I have open.”'],
    ],
  },
  {
    slug: 'plan-mode',
    title: 'Plan mode',
    date: '2026-10-18',
    starring: 'Sunny and Judy',
    deck: 'Sunny wants one button renamed. Judy, the Plan agent, brings a 38-step plan, and step 38 is the rename.',
    inside: 'Inside: when a plan pays off, and when to skip it.',
    alt: 'Four-panel comic. Sunny, at his terminal, to Judy: “Rename one button. Just do it.” Judy at a blank chalkboard, chalk raised: “First, a plan.” A chalk flowchart covers the whole wall, tagged “Plan · 38 steps”, while Judy adds a box from a stepladder. Sunny reads the last box: “Step 38: rename the button.” Judy holds out the chalk: “Approve?”',
    headline: 'Plan mode: a 38-step plan to rename one button in Claude Code',
    description:
      'A four-panel comic about Claude Code planning a one-button rename in 38 steps, and when plan mode is worth it and when to just ask for the change.',
    lead: 'Sunny asks for one renamed button. Judy, the Plan agent, wants a plan first, and the plan takes the whole wall.',
    panels: [
      ['1', 'Sunny, at his terminal, to Judy: “Rename one button. Just do it.”'],
      ['2', 'Judy at a blank chalkboard, chalk raised: “First, a plan.”'],
      ['3', 'A chalk flowchart covers the wall. The tag reads “Plan · 38 steps”. Judy adds one more box from a stepladder.'],
      ['4', 'Sunny reads the last box: “Step 38: rename the button.” Judy holds out the chalk: “Approve?”'],
    ],
  },
  {
    slug: 'compact',
    title: 'Compact',
    date: '2026-10-18',
    starring: 'Walt and Felix',
    deck: 'Context at 99 percent. Felix boxes the whole conversation into a summary, and the summary remembers a login button.',
    inside: 'Inside: what compaction keeps, and how to keep the rest.',
    alt: 'Four-panel comic. Walt points at a gauge in the red: “Context at 99 percent.” Felix pushes a mountain of printouts into one small box. The box sits taped shut on a desk, tagged “Compacted”, and Walt’s voice asks: “So, what were we building?” Felix reads a single card from the box while Walt scratches his head: “Something with a login button.”',
    headline: 'Compact: what Claude Code keeps when the context fills up',
    description:
      'A four-panel comic about a whole conversation compacted onto one card, and how to steer what Claude Code keeps when the context window fills up.',
    lead: 'The context is at 99 percent, so the whole conversation goes into one small box. Afterwards, nobody can quite say what they were building.',
    panels: [
      ['1', 'Walt points at a gauge in the red: “Context at 99 percent.”'],
      ['2', 'Felix pushes a mountain of printouts into one small box.'],
      ['3', 'The box sits taped shut on a desk. The tag reads “Compacted”. Walt, from outside the panel: “So, what were we building?”'],
      ['4', 'Felix reads a single card from the box while Walt scratches his head: “Something with a login button.”'],
    ],
  },
];
