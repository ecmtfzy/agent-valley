# Changelog

## 0.2.0 — 2026-10-20

We moved house. AgentValley is now an app you download, signed with a Developer ID and checked by Apple.

- Download AgentValley.dmg and drag it into Applications. With Homebrew: `brew install --cask morsechimwai/tap/agent-valley`.
- We check GitHub for a new version once a day and ask before we install it. The switch, and Check now, are in Settings.
- Open us from the dmg or from Downloads and we'll offer to move ourselves to Applications.
- Only one of us runs at a time. Open another copy and the old one steps out.
- On 0.1 from Homebrew? Run `brew uninstall --formula agent-valley`, then download the dmg or install the cask. Homebrew won't move you over by itself.
- The plugin may still point at the old copy. The panel says so when it does; copy its command from Settings once more.
- Put the crew in Claude Code's terminal on 0.1? Its status line still calls the old copy and goes blank once that's gone. Copy the crew's install command from the Actions settings and run it once more.
- To macOS we're a new app, so it may ask again: to let us work your terminal when you jump to an agent, and, with Plan limits on, to read your Claude Code login from the Keychain.

## 0.1.4 — 2026-10-19

- At work, we hold what the agent is on: a printout while it reads, a keyboard while it edits, a terminal while it runs a command, a magnifier while it searches, a phone while a sub-agent works for it, and a chin in one hand while it thinks. Six seconds in hand, two to put it down. The faces in Claude Code's terminal hold the same things, standing still. Reopen your terminal once after updating to see them there.
- Report a bug, in Settings, opens a new GitHub issue with the app's version, macOS and Mac model filled in. Your browser sends it; the app still sends nothing.
- Long transcripts open faster and take far less memory. A 116 MB one used to take 0.96 s and 314 MB more memory, and now takes 0.41 s and 12 MB. History's first pass over a big folder of transcripts is about three times quicker.
- The status line's context meter says `context`, not `ctx`.
- The crew's font is a quarter of its old size.

## 0.1.3 — 2026-10-17

- History has its own button at the top of the panel, a chart beside the pin. The token line at the end of the list still opens it, but it never looked like something to press.

## 0.1.2 — 2026-10-17

- The crew comes to Claude Code's terminal too. The status line under the prompt gets the face of whoever runs the session, with the model, your plan and your limits, and each sub-agent row gets a face, its model and its current step. Set it up in the Actions settings, under Crew in the terminal. It keeps working with the app closed. Tried in Terminal, iTerm2, Ghostty and Cursor.
- Export PDF, at the top of History, makes an A4 report of the day, week or month on screen. Press it on All projects for every project, or on one project for its sessions alone, with no other project's name in it, to hand to a team or a client.
- If you remove the app, take the crew out of the terminal first, with the command under How to take it out in the Actions settings. Otherwise Claude Code's status line goes blank.

## 0.1.1 — 2026-10-16

- Open at login keeps working after `brew upgrade`. macOS remembers the app by its folder, and Homebrew gives each version a new one; the app now tells macOS where it is when it opens from a new folder. If you turned Open at login on in 0.1.0, quit the app and open it again after upgrading.

## 0.1.0 — 2026-10-16

The first public release.

- Every Claude Code session gets a card in the notch, and every agent and sub-agent a row with its task, model and latest step.
- A red count beside the notch when an agent asks a question or waits for permission.
- Jump to the agent's app in one click.
- Allow once or Deny from the notch, with a plugin you install yourself.
- History: what each project cost by day, week or month, at API prices.
- Plan limits, token use, and a keyboard shortcut (⌃⌥⌘A).
