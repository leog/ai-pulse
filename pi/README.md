# AI Pulse ⇄ pi

A [pi](https://github.com/earendil-works/pi) extension that mirrors the
active pi session onto the AI Pulse light strip, so the ambient LEDs beside
your Dock reflect what pi is doing — exactly like the built-in Claude Code
integration, but for pi.

It uses the same loopback HTTP API and handshake file as the `aipulse` CLI
(`127.0.0.1:7455`, bearer token, `/v1/agents/upsert`), so **no changes to AI
Pulse itself are required** — you only need the app running and this one
TypeScript file loaded as a pi extension.

## Install

1. Make sure **AI Pulse** is running once (it writes the credential
   handshake file on launch).
2. Copy the extension into pi's auto-discovered extension folder:

   ```sh
   mkdir -p ~/.pi/agent/extensions
   cp pi/aipulse-pi.ts ~/.pi/agent/extensions/
   ```

   (or drop it in a project's `.pi/extensions/` for project-local use)
3. Reload pi: `/reload` (or restart pi). You'll see the extension load.

That's it. The light strip now tracks pi. When pi is running a turn it goes
cyan/working, when it's blocked asking you a yes/no question it breathes
orange/approval, when a turn completes it's green/completed, and when it's
idle waiting for your next prompt it waits in orange.

> **Never breaks pi:** every publish is fire-and-forget and swallowed on
> failure. If AI Pulse isn't running or is unreachable, pi is completely
> unaffected. No prompt text, tool inputs, or outputs are ever read.

## How it maps

| pi event | AI Pulse state | Notes |
|----------|----------------|-------|
| `session_start` | `idle` | "Session started / resumed" |
| `before_agent_start` | `working` | a prompt was submitted |
| `tool_execution_start` | `working` | "Running `<tool>`" |
| `tool_execution_start` (`ask_question`) | `approvalRequired` | pi is blocked on your answer |
| `agent_end` | `completed` | turn finished |
| `agent_settled` | `waitingForInput` | whole run done; pi idle awaiting input |
| `session_shutdown` | removed | `/quit`, `/new`, `/resume`, `/fork` |

One AI Pulse entry per pi session per project (`pi:<cwd>:<session-id>`).

## Tuning

- **Port / token** — honored env overrides, matching the `aipulse` CLI:
  `AIPULSE_PORT`, `AIPULSE_TOKEN`, and `AIPULSE_CONFIG` (handshake path).
- **Icon** — the adapter sends SF Symbol `"terminal"`. For a branded color
  + glyph, add a `"pi"` entry to `ProviderIconCatalog.styles` in
  `Sources/AIPulse/Presentation/Pill/ProviderIconCatalog.swift` and rebuild.
- **Approval detection** — the built-in `ask_question` tool is treated as an
  approval prompt. Custom permission gates that block inside `tool_call`
  won't be detected as `approvalRequired`; extend the `tool_call` handler if
  you need that (the event can `return { block: true, reason }`).
