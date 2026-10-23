import type { Strip } from '../../strips';

// Strip nine waits here, out of the site, until Tuesday 27 October 2026. Folders that start with _
// are never pages. To publish it: move this folder back to app/comics/both-on-main, add the strip
// below to the end of STRIPS in strips.ts (this file can go), point page.tsx's import back at
// '../comic-page', and check the date.
export const BOTH_ON_MAIN: Strip = {
  slug: 'both-on-main',
  title: 'Both on main',
  date: '2026-10-27',
  starring: 'Norm and Pearl',
  deck: 'Two tasks, two sessions, one folder. Norm and Pearl both need LoginView.swift, and both of them are on main.',
  inside: 'Inside: how to give each session a worktree of its own.',
  alt: 'Four-panel comic. 10:00, Norm and Pearl at their terminals, side by side. From off the panel: “Norm, fix the login. Pearl, add dark mode.” 10:40, the two pull one long printout between them. Norm: “I need LoginView.swift.” Pearl: “So do I.” Then the printout lies torn in half on a floor of crumpled paper and loose tape, tagged “CONFLICT”: “Which branch were you on?” Both: “main.” 11:30, the AgentValley panel shows two sessions, Fix the login and Add dark mode, both in shop-web on main, both on “Edit LoginView.swift”. Pearl: “It said so at ten.”',
  headline: 'Both on main: two Claude Code sessions in the same folder',
  description:
    'A four-panel comic about two Claude Code sessions editing the same file on the same branch, and how to give each session its own git worktree.',
  lead: 'Two tasks, two Claude Code sessions, one folder. They meet in the same file, on the same branch, before anyone looks.',
  panels: [
    ['10:00', 'Norm and Pearl at their terminals. You, from off the panel: “Norm, fix the login. Pearl, add dark mode.”'],
    ['10:40', 'The two pull one long printout between them. Norm: “I need LoginView.swift.” Pearl: “So do I.”'],
    ['Later', 'The printout lies torn in half on a floor of crumpled paper and loose tape. The tag reads “CONFLICT”. You: “Which branch were you on?” Norm and Pearl: “main.”'],
    ['11:30', 'The AgentValley panel: both sessions in shop-web, both on main, both on “Edit LoginView.swift”. Pearl: “It said so at ten.”'],
  ],
};
