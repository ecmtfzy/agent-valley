# Codex integration

This fork adds Codex support to AgentValley. The `codex-support` branch contains
the adapter; `main` follows the original AgentValley project. Codex and Claude use
the same session cards, agent rows, status indicators, approval views, navigation,
and history.
There is no Codex title prefix, separate panel, or provider-specific visual theme;
the existing model label identifies the model in use.

## Requirements

- macOS 15 or later. AgentValley is a native Mac app designed for a MacBook notch;
  this integration does not add Windows or Linux support.
- Xcode or compatible Apple Command Line Tools, a Swift toolchain that can build
  the project, and an installed macOS SDK. SwiftPM fetches the project's declared
  dependencies when needed.
- Python 3. The bridge and runtime helper use the standard library. The packaged
  runtime reader invokes `/usr/bin/python3`, so that executable must be available.
- A Codex CLI with command hooks and `app-server proxy` support. The integration
  was tested against `0.164.0-alpha.11.1`; hook and app-server compatibility should
  be checked when upgrading Codex.
- For live runtime status, metadata and account limits, a running local Codex
  desktop daemon. Exact-thread navigation currently verifies the desktop bundle
  at `/Applications/ChatGPT.app`, its `com.openai.codex` bundle identifier, and its
  registered `codex` URL scheme. A differently packaged installation may need an
  adapter update.

## Build and install

Clone this fork's `codex-support` branch, then run commands from the repository
root. Select the intended Apple developer tools with `DEVELOPER_DIR` if needed;
`xcrun` reports the selected compiler and SDK:

```sh
xcrun --find swift
xcrun --sdk macosx --show-sdk-path
./build-app.sh build
codesign --verify --deep --strict build/AgentValley.app
```

If the selected toolchain's default build engine requires full Xcode, the script
supports the native-engine override. `SDKROOT` can select an installed, compatible
SDK explicitly; this example discovers it instead of assuming a versioned path:

```sh
SWIFT_BUILD_SYSTEM=native \
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
./build-app.sh build
```

The build script also handles the missing SwiftUI macro plugin in some Command
Line Tools installations by selecting an available older SDK. A compatible SDK
must actually be installed. With Command Line Tools, the output may target only
this Mac's architecture. Local bundles are ad-hoc signed unless `SIGN_IDENTITY`
is supplied; the build command does not notarize them.

Quit AgentValley and back up any installed app, existing hook configuration, and
AgentValley settings/data before replacing a working installation. Copy
`build/AgentValley.app` to Applications using Finder. Keep the backup outside the
source checkout. A later official AgentValley installation can replace this fork;
local builds have no automatic update feed unless one is explicitly configured.

### Configure hooks

Generate a fragment from the installed app so hook commands keep working if the
source checkout moves. Use a persistent Python installation: the generated
commands retain the interpreter path used here.

```sh
mkdir -p build/codex-setup
python3 /Applications/AgentValley.app/Contents/Resources/codex/bridge.py config \
  --events "$HOME/Library/Application Support/AgentValley/codex/events.jsonl" \
  --answers --messages --display-inputs \
  > build/codex-setup/agentvalley-hooks.json
```

The optional flags enable the existing notch approval controls, Away message
relay, and tool-step summaries respectively. Omit them for lifecycle observation
only. Review the data-handling section below before enabling tool-step summaries.

Merge the generated event groups into the hook configuration used by your Codex
installation. The tested CLI reads `$CODEX_HOME/hooks.json`, normally
`~/.codex/hooks.json`. Preserve unrelated event groups and handlers. When updating
an earlier AgentValley configuration, replace its handlers rather than adding
another copy. On Codex versions requiring the feature flag, enable `hooks = true`
in the existing `[features]` section of the Codex configuration; do not duplicate
that section or overwrite other settings.

Review the definitions through Codex's normal `/hooks` flow and approve only the
intended configuration/project scope. Existing sessions may need a new turn or
session to load the change. The bridge creates its private journal on the first
hook event. Launch or restart AgentValley after that file exists; Finder and login
launches then discover it automatically. `AGENTVALLEY_CODEX_EVENTS` is an optional
absolute-path override and must agree with the hook's `--events` path.

In AgentValley Settings, turn on **Answer from the notch** to use Allow/Deny.
**Token use**, **Claude plan limits**, and **Codex plan limits** retain their own
switches. Enabling Codex plan limits does not enable Claude limits or request
Claude credentials. Keep Codex running for metadata and quota reads.

## Shared interface and adapters

The integration supplies the existing `SessionCard`, `AgentInfo`, `OwnerApp`,
`AnswerStore`, and `UsageLedger` interfaces. The internal `codex-` ID namespace
prevents session collisions; it is not a displayed label.

| Existing feature | Codex data or action |
| --- | --- |
| Working, needs-you, quiet, done; animations and sounds | Lifecycle hooks and live runtime status |
| Session title, project, branch, model | Thread metadata and the existing project path formatting |
| Subagent rows and completed-agent folding | Lifecycle hooks plus verified child metadata |
| Current tool step | Bounded hook display fields, formatted by the existing tool-label code |
| Allow / Deny in the notch | Permission hook relayed to the existing local approval socket |
| Name click, Go to, keyboard navigation | Existing OwnerApp behavior with a verified desktop thread link |
| Token footer and History | Real token counts from tracked local Codex rollouts |
| Plan limits | Read-only Codex account quota, using the existing meters |
| Existing phone/Away delivery backend | Stop-hook relay into the existing StopDesk queue |

The message path reuses upstream's phone/Away infrastructure. It does not add a
visible composer, input window, or messaging interaction. A queued user message is
delivered through the Stop hook only while Away is enabled. Without Away or a
queued message, this path supplies no new instruction.

## Lifecycle and approvals

`Codex hook → bridge.py → private JSONL journal → CodexEventStore → shared cards`

The existing one-second store tick consumes the journal. `CodexSessionMetadata`
adds real titles and available child/model/project metadata on a separate bounded
worker. Card refresh never opens project Git files: a cloud placeholder or filesystem
permission prompt must not block all sessions. Branch names come from daemon metadata.
Checkout/worktree relationships are not inferred by opening project directories;
when the daemon does not provide them, grouping uses the existing path-name fallback
and no worktree marker is invented.
The runtime helper connects to the already-running local daemon with
`codex app-server proxy`; it does not start another daemon. This connection sends
only `initialize`, `initialized`, and `thread/read` with `includeTurns: false`
for session status. With Codex plan limits enabled, a separate bounded fetch uses
`account/rateLimits/read`. Neither mode approves a request or resumes a session.

| Event | Result |
| --- | --- |
| SessionStart | Session present, initially quiet |
| UserPromptSubmit | Working |
| PreToolUse / PostToolUse | Tool activity / tool result |
| PermissionRequest | Needs you; existing approval UI when enabled and displayable |
| PermissionResolved | An explicit notch decision clears only its own request |
| SubagentStart / SubagentStop | Child row starts / finishes |
| Stop / Interrupt | Main turn finishes / is interrupted |
| SessionEnd | Session closes |
| PreCompact / PostCompact | Compaction / continuation |

`PermissionResolved` is an internal bridge event, not an additional native hook.
Every relayed permission has its own request ID. Unknown, duplicate, or unrelated
resolution events cannot clear another pending request. The existing **Answer
from the notch** switch controls the socket and its Allow/Deny UI. Only an explicit
user click or the existing guarded keyboard action sends a decision. Closing the
app, timeout, a missing socket, or an invalid reply supplies no permission decision.
The bridge accepts once-only Allow/Deny replies, not permanent rules or rewritten
tool inputs.

If the person answers inside Codex instead, native hooks lack an approval-resolved
event. For a single unambiguous wait, the runtime reader first observes
`waitingOnApproval` and then its transition to active without waiting flags. It can
restore working before a long command returns. Overlapping or ambiguous requests
retain conservative hook-based behavior. A confirmed live wait remains visible
beyond the hook reader's one-hour quiet timeout.

## Local data handling

The journal is a mode-0600 regular file owned by the user, with bounded append
locking and a 16 MiB cap. It records lifecycle names, identifiers, cwd, model,
tool/agent names, receipt times, and explicit resolution metadata.

The optional `--display-inputs` handler additionally stores selected fields from
`PreToolUse`: command, description, file/path, pattern, query, URL, and name. Each
field is bounded to 2 KiB and the complete display object to 8 KiB; shortened values
carry an ellipsis. These summaries are for the shared step line only. They are
never used as the full input for an approval decision. Arbitrary tool arguments,
tool results and conversation prompts are not copied into the journal. The bridge does
not read credentials or environment variables; a selected command field can still
contain sensitive text supplied as part of the command.

For an interactive permission, the complete tool input travels in memory over the
existing same-user local socket so the approval view can determine whether it can
display the entire request. The socket path and peer identity are checked. The
bridge does not persist that complete payload. A request that cannot be shown in
full does not gain an Allow button through a truncated summary. Failures return an
empty hook result and leave Codex in control.

Metadata reads retain bounded fields needed by cards, including a task preview for
a verified child. Token-history reads keep usage counts and context metadata in
the existing SQLite ledger, not transcript text or account credentials.

## Token history

`CodexUsageReader` reads session IDs from Codex's local session index and
AgentValley's journal, including UUIDs identified by parent subagent events.
Existing indexed history can be imported even if it predates the hooks. It looks in their possible
date folders and archived-rollout names rather than scanning all conversation
contents. A rollout must identify the expected session. Incremental offsets and
usage context are stored in the ledger transaction so restarts do not recount
cumulative usage. Session titles come from the local session index. Codex-only
history does not open project Git files; existing checkout mappings and path
formatting supply project names without accessing cloud placeholder repositories.

Codex input totals include cached input; the adapter separates new input, cache
reads, and reported cache writes. Reasoning tokens are already included in output
and are not added twice. Child usage is grouped with its parent session while
retaining the child's actual model. Inherited usage predating a fork's creation is
not charged to the fork.

GPT models without a verified price-table entry display their names and actual
unpriced token counts in History, including project and session rows. They are
not hidden in the model summary's `others` category. Unknown totals use `—`, and
the money chart explicitly excludes unpriced usage. Claude prices are never substituted.
This is usage history, not the user's actual subscription bill.

## Codex plan limits

The independent Codex plan-limits switch reads the already-running local Codex
daemon using `account/rateLimits/read`. It does not read auth files or Keychain
credentials, launch a second daemon, log in or out, buy credits, or consume a reset.
The helper retains only the Codex bucket, usage percentages, window durations,
reset timestamps and the minimal availability metadata; account identifiers,
credit balances and reset-credit details are discarded.

`rateLimitsByLimitId.codex` is authoritative when a map is present; an empty or
unrecognized map never falls back to a different legacy bucket. Windows are
mapped by their durations: 300 minutes to 5h and 10080 minutes to 7d. Primary
does not necessarily mean 5h: a weekly window may be returned as primary. Missing
windows stay absent, never 0%. Other window durations are not mislabeled as 5h
or 7d.

The existing refresh/stale-data policy is reused independently for each provider:
periodic refresh every five minutes, refresh on opening after one minute, failure
annotation on retained data, and expiry after fifteen minutes. Disabling Codex
limits cancels its in-flight fetch and clears its displayed data. When both
providers are enabled, their source-labelled rows reuse the same meter component;
account values and errors never replace one another. It does not
enable Claude limits or request Claude credentials. Codex exhaustion scenes need
explicit backend denial of ordinary usage and a fully used window; percentages
or a passed reset time cannot establish that Codex is available again. Missing
permission status also resets the availability-sound baseline rather than
announcing a recovery. Global exhausted scenes are suppressed for mixed-provider
sessions, since one account cannot describe every agent.

The collapsed bar uses concentric quota rings: Claude stays on the outside and
Codex on the inside, including with mixed sessions or no active sessions. Each
account uses its 5-hour window when available, otherwise its weekly window; the
tooltip and accessibility label name the account, ring position, window and
percentage. Missing or disabled account data hides only that account's ring.
The existing longest-wait reminder still takes priority over the rings.

## Verification

Run the Python regressions and isolated hook-discovery check from the repository
root. Discovery requires a compatible `codex` executable; pass `--codex` with its
path if it is not on `PATH`.

```sh
python3 -m unittest discover -s integrations/codex -p 'test_*.py' -v
python3 testing/test-probe-codex-runtime.py
python3 testing/check-codex-hooks.py "$PWD/build/codex-setup/agentvalley-hooks.json"
```

Hook discovery uses a temporary `CODEX_HOME` with network access denied. It does
not execute hooks, run a model, or grant trust. The `codex-status` diagnostic exits
before GUI startup and reads hook-derived cards; live metadata enrichment is
separate. Normal GUI launch closes other app copies with the same bundle ID, so
use the diagnostic for isolated journal checks.

With full Xcode and XCTest available, run the complete suite:

```sh
swift test
```

Focused smoke runners are also available:

```sh
python3 testing/codex-smoke.py build/AgentValley.app/Contents/MacOS/AgentValley
python3 testing/codex-runtime-smoke.py
python3 testing/codex-metadata-smoke.py
python3 testing/codex-usage-smoke.py
python3 testing/codex-message-smoke.py
python3 testing/codex-limits-smoke.py
```

The Swift smoke runners discover the compiler and SDK through the shared test
helper. They honor `DEVELOPER_DIR` and `SDKROOT` (an SDK path or SDK name such as
`macosx`). Without an explicit developer directory, they prefer installed Command
Line Tools before falling back to the default `xcrun` selection. They compile
production logic with small replacements for XCTest and unrelated dependencies;
they do not replace the complete XCTest suite. Reports and temporary fixtures are
written under the ignored `build/codex-prototype/` directory.
Run `python3 testing/codex_test_toolchain.py` to inspect the selected toolchain
without compiling or changing its configuration.

Regression coverage includes overlapping approvals, unknown/duplicate resolution
protection, runtime recovery, proxy cleanup, metadata/navigation, incremental
SQLite usage import, StopDesk message delivery, quota parsing, independent account
settings, and source isolation. Synthetic hook replays exercise the diagnostic
without opening the GUI. Quota tests include weekly-as-primary responses, missing
windows, stale data, subprocess cancellation, and the original Claude behavior.

Manual real-session checks on macOS have also verified the shared approval card,
Deny, Allow once, return to working before a long command finishes, idle after
completion, History imports, and simultaneous Claude/Codex quota rows. These
checks used real account responses; no account-specific data is needed by the
regression fixtures. Paired-phone end-to-end delivery and visual confirmation of
the Go-to destination are not covered by those checks.

## Maintaining the fork

Use `origin` for your writable GitHub fork and `upstream` for the original project
at `https://github.com/morsechimwai/agent-valley.git`. Treat `upstream` as read-only.
The fork's default branch is `codex-support`, which keeps the Codex adaptation;
`main` follows `upstream/main` without Codex-specific commits.

Verify the remotes before updating:

```sh
git remote -v
```

If `upstream` has not been configured, add and fetch it:

```sh
git remote add upstream https://github.com/morsechimwai/agent-valley.git
git fetch upstream
```

Set the local `main` branch to track `upstream/main`. If the local `main` branch is
missing, create it with `git branch --track main upstream/main`; otherwise use
`git branch --set-upstream-to=upstream/main main`. Confirm `origin` points to your
fork before pushing. Do not put adaptation commits on `main`.

For each update, start with a clean working tree, fetch upstream, and merge its
changes into the adaptation branch:

```sh
git fetch upstream
git switch main
git merge --ff-only upstream/main
git switch codex-support
git merge upstream/main
```

Resolve any merge conflicts on `codex-support`, run the verification commands
above, rebuild with `./build-app.sh build`, and verify the resulting bundle with
`codesign --verify --deep --strict build/AgentValley.app`. Review changes affecting
hooks, approvals, runtime status or account limits before installing the new
bundle. Once the checks pass, publish the updated adaptation to your fork:

```sh
git push origin codex-support
```

You can also synchronize the fork's unmodified base branch with
`git push origin main`. This workflow does not push to upstream or open an
upstream pull request. Track Codex-adapter work in this fork.

## Compatibility and remaining boundaries

- Local CLI/shared-desktop execution with command hooks is supported. Discovery
  was checked against Codex CLI `0.164.0-alpha.11.1`. Existing sessions may
  need a new turn/session to load changed definitions.
- Cloud orchestration and hosted tools do not necessarily emit local hooks. No
  cloud-task coverage is claimed. Independent embedded runtimes are not assumed
  observable through the desktop daemon.
- Exact-thread navigation requires the verified desktop bundle and its registered
  `codex` URL scheme. Missing metadata does not invent a destination, title, child
  model, or message route.
- The permission bridge supports Allow/Deny. Question/plan protocols that cannot
  accept the corresponding answer are not presented as working option buttons;
  answer those in Codex. General asynchronous questions still need a separate
  supported lifecycle contract.
- Codex plan limits need the local shared daemon and a supported ChatGPT account
  quota response. Only the Codex bucket and 5h/7d windows are displayed. Unknown
  windows or missing data are unavailable rather than fabricated. No purchase or
  quota-reset actions are exposed.
- Usage import covers tracked plain `.jsonl` rollouts, not a full-account backfill
  or compressed `.jsonl.zst` history. Imported records stay in SQLite. Unknown GPT
  API prices remain unknown.
- The journal has a 16 MiB cap and no automatic rotation. Delivery failures supply
  no decision. If live status is unavailable or ambiguous, the hook-only fallback
  may fade a permission wait after an hour.
- No terminal status-line integration or extra visible composer is added. The
  integration reuses upstream features rather than adding new surfaces.

## Sources

- [AgentValley source and build instructions](https://github.com/morsechimwai/agent-valley)
- [Codex lifecycle hooks and trust](https://learn.chatgpt.com/docs/hooks)
- [Codex app-server](https://learn.chatgpt.com/docs/app-server)
