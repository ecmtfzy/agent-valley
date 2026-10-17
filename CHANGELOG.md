# Changelog

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
