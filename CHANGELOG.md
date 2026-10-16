# Changelog

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
