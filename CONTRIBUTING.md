# Contributing to AI Pulse

Thanks for your interest! AI Pulse is a small, carefully-scoped macOS app.
This document explains how the codebase is organized, the invariants that
keep it trustworthy, and what a good pull request looks like.

## Getting started

```sh
git clone <your-fork>
cd ai-pulse
swift build          # app + CLI + kit
swift test           # the whole suite — fast, deterministic, no UI needed
swift run AIPulseApp # run the pill from the debug build
```

Requirements: macOS 14+, Swift 6 toolchain (Xcode 16+). No third-party
dependencies — please keep it that way; every dependency is an audit burden
for an app that sits on people's screens all day.

For day-to-day running, prefer the signed bundle (`./Scripts/make-app.sh`)
so Keychain trusts the app across rebuilds. For quick dev loops, launch
with `AIPULSE_DEV_EPHEMERAL_TOKEN=1` to skip the Keychain entirely.
[docs/DEBUGGING.md](docs/DEBUGGING.md) lists every debugging affordance.

## Architecture in one paragraph

`Sources/AIPulseKit` is an AppKit-free library holding all logic: the
domain model, the `AgentReducer` that validates every inbound event, the
`AgentStore` single source of truth, timing rules in `StalenessPolicy`,
placement math, and the HTTP transport. `Sources/AIPulse` is the app shell:
SwiftUI/AppKit surfaces (pill, hover card, agent list, settings, Dock tile)
that *only* render store state, plus controllers that own timers, windows,
and the server lifecycle. `Sources/AIPulseCLI` is the `aipulse` publisher
CLI, including the Claude Code hook entry point.

## Invariants — please don't break these

1. **AIPulseKit stays AppKit-free and fully tested.** If logic can live in
   the Kit, it should, with unit tests. UI targets hold no business rules.
2. **`AgentStore.apply` via `AgentReducer` is the only mutation path for
   inbound events.** Sequencing, validation, and capping happen there once,
   not per-surface.
3. **All timing decisions live in `StalenessPolicy`.** No view or
   controller ever compares timestamps on its own.
4. **Privacy boundary at the adapter.** Integration adapters decode only
   status metadata (event names, tool *names*, notification text). Prompt
   content, tool inputs/outputs, and assistant messages are never decoded,
   so they can never be published. New adapters must document and honor
   this line.
5. **No private APIs, no Accessibility or Screen Recording permissions, no
   injection.** Placement uses public screen geometry only; degrade
   gracefully rather than escalate permissions.
6. **Events are data, never commands.** Typed actions only
   (`openURL`/`activateApplication`/`showDetails`), URL schemes
   allowlisted, everything length-capped. Nothing received over the wire
   is executed or interpreted.
7. **Determinism in tests.** Dates, process-liveness checks, and process
   ancestry lookups are injectable. New timing- or process-dependent code
   should follow the same pattern — a test must never sleep or depend on
   the host machine's state.

## Making changes

- **Kit changes** need unit tests in `Tests/AIPulseKitTests`, matching the
  existing style (plain `XCTest`, injected clocks, no mocking frameworks).
- **UI changes** should include before/after PNGs rendered with the
  headless snapshot mode — `swift run AIPulseApp --snapshot /tmp/snaps` —
  which needs no Screen Recording permission and renders the pill, hover
  card, and the settings window (the settings capture exercises the real
  window-controller path, which has caught real sizing bugs).
- **Comment style:** comments state constraints and invariants the code
  can't express ("never on the main thread", "0600 because…"), not
  narration of what the next line does.
- **New agent integrations:** follow `ClaudeCodeAdapter` as the template —
  a pure `map(input) -> AgentEventPayload?` function in
  `Sources/AIPulseKit/Integrations/`, documented against the tool's
  published lifecycle, tests for every state transition, and the privacy
  boundary honored. Third-party tools can also integrate with no code at
  all via the `aipulse agent upsert` CLI or the local HTTP API (see
  README).

## Pull requests

- One concern per PR; small is welcome.
- `swift test` must pass; add coverage for what you changed.
- Imperative-mood commit subjects ("Add X", "Fix Y"), body explains *why*
  when it isn't obvious.
- If behavior visible to users changed, update README.md; if you added a
  debugging affordance (env var, flag, snapshot), document it in
  docs/DEBUGGING.md.

## Releases

Merging a PR into `main` automatically builds the app bundle and publishes
a GitHub Release. The semver bump is **patch** unless the PR is labeled
`release:minor` or `release:major` — apply the label before merging when
your change warrants it. Maintainers can also cut a release manually from
the Actions tab (Release → Run workflow).

## Reporting bugs

Open an issue with: macOS version, how you launched the app (signed bundle
vs `swift run`), what the pill showed vs what you expected, and — if it's
a state question — the contents of
`~/Library/Application Support/AIPulse/agents.json` (it contains only
status metadata, never prompt or code content, but skim it before pasting).
The debugging guide's [common failure modes](docs/DEBUGGING.md#common-failure-modes)
section may resolve it immediately.
