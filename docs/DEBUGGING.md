# Debugging AI Pulse

Everything here works without Screen Recording, Accessibility, or any
other permission grant.

## Where state lives

| Path | What it is |
| --- | --- |
| `~/Library/Application Support/AIPulse/agents.json` | Persisted agent snapshot (status metadata only). Safe to delete; the app rebuilds it. |
| `~/Library/Application Support/AIPulse/cli.json` | CLI handshake (port + bearer token, mode 0600). Rewritten on every server start. |
| Keychain item (service `AI Pulse`) | The stable bearer token, ACL-bound to the app's code signature. |
| `defaults read me.leog.aipulse` | User settings (placement, appearance, staleness thresholds, port). |

On restart the app rehydrates `agents.json` through `RestorePolicy`:
waiting/approval/failed agents come back as-is; working/idle/unknown come
back as `disconnected` until their source reports again.

## Environment variables and flags

| Variable | Effect |
| --- | --- |
| `AIPULSE_DEV_EPHEMERAL_TOKEN=1` | Skip the Keychain; generate a per-run token and rewrite the handshake file. Use for every dev loop with unsigned/`swift run` builds. |
| `AIPULSE_DEMO_AGENTS=1` | Seed mock agents at launch when the store is empty (UI work without live sessions). |
| `AIPULSE_DEBUG_HOVER_X=<x>` | Simulate a pointer at view x-coordinate shortly after launch, so hover-card rendering can be verified headlessly. |
| `--snapshot <dir>` (app argument) | Render pill, hover card, and the settings window to PNGs and exit. The settings capture goes through the real `SettingsWindowController`, so window-sizing regressions show up here. |
| `AIPULSE_PORT` / `AIPULSE_TOKEN` / `AIPULSE_CONFIG` (CLI) | Override the CLI's connection details or handshake file path. |

## Logs

```sh
log stream --level info --predicate 'subsystem == "me.leog.aipulse"'
```

The server logs listen/failure there. Silence from the `server` category
after launch means startup never completed — see the Keychain hang below.

## Poking the system by hand

```sh
aipulse health                       # is the server up?
aipulse agents                       # everything the pill knows, as JSON

# Simulate any state without a real agent:
aipulse agent upsert --id demo:1 --name Demo --provider test \
  --state approvalRequired --message "Deploy to prod?"
aipulse agent remove --id demo:1

# Feed the Claude Code adapter a synthetic hook event:
echo '{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"'$PWD'","tool_name":"Bash"}' \
  | aipulse claude-hook
```

`claude-hook` is deliberately silent and always exits 0; to watch what it
publishes, run `aipulse agents` afterwards, or point it at a scratch
listener with `AIPULSE_PORT`/`AIPULSE_TOKEN` and capture the request.

## Agent lifecycle timing (who clears what, and when)

| Situation | Rule | Default |
| --- | --- | --- |
| Working agent goes quiet | Marked *stale* (dimmed, still working) | 10 min, configurable |
| Working agent quiet much longer | Demoted to `disconnected` | 30 min, configurable, "never" supported |
| Agent's backing process exits | Demoted to `disconnected` on the next sweep — integrations may publish a `pid`; the sweep checks it with `kill(pid, 0)` (only `ESRCH` counts as dead) | ≤ 30 s |
| `completed` agent | Removed | 60 s, configurable |
| `waitingForInput` / `approvalRequired` / `failed` | Never expire on timers — resolved by a new state, source-provided `expiresAt`, or user action | — |

The sweep runs every 30 seconds (`StoreMaintenanceController`); all rules
live in `StalenessPolicy` and `AgentStore.sweep`.

## Common failure modes

**`aipulse: could not reach AI Pulse` while the app is running.**
The server never started because the Keychain token read is blocked on a
consent dialog — typically after the binary's code signature changed (new
checkout, different signing identity, ad-hoc `swift run` build) so the
existing Keychain item's ACL no longer matches. There may be a SecurityAgent
prompt hiding behind other windows; click **Always Allow** once. For dev
loops, launch with `AIPULSE_DEV_EPHEMERAL_TOKEN=1` instead. The hang is
silent by design (the token read happens off the main thread so the pill
still appears) — absence of any `me.leog.aipulse` log line is the tell.

**An agent shows "working" but nothing is running.**
A source that dies mid-turn can't send a terminal event. The liveness check
and silence demotion (table above) clear it within seconds-to-minutes
depending on whether the integration published a `pid`. If you see one
stuck forever, the event's `pid` was probably missing or wrong — check the
entry in `agents.json`.

**Settings/hook can't find `aipulse`.**
This repo's `.claude/settings.json` invokes the *debug* build path
(`.build/debug/aipulse`); run `swift build` after cloning or the hooks
silently no-op. System-wide installs should copy the release binary to a
stable path instead (see README).

**Swift build errors about `ModuleCache` / `SwiftShims` after copying a
checkout.** `.build` contains absolute paths; a `.build` directory copied
from another checkout poisons compilation. `rm -rf .build/<arch>/<config>/ModuleCache`
(or the whole `.build`) and rebuild.

**Two instances fighting over the port.** Only one AI Pulse can bind
127.0.0.1:7455. The second instance's server fails to start (logged), and
whichever instance wrote `cli.json` last owns the CLI. Quit one.
