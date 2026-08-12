# AI Pulse ⇄ pi

A [pi](https://github.com/earendil-works/pi) extension that mirrors the
active pi session onto the AI Pulse light strip, so the ambient LEDs beside
your Dock reflect what pi is doing — exactly like the built-in Claude Code
integration, but for pi. It also **opens and closes with pi**: if AI Pulse
isn't running when pi starts, the extension launches it; when pi shuts down,
no other agents are using AI Pulse, and the extension itself was the one that
launched the app, it quits it — an instance you started yourself is never
touched.

It uses the same loopback HTTP API and handshake file as the `aipulse` CLI
(`127.0.0.1:7455`, bearer token, `/v1/agents/upsert`), so **no changes to AI
Pulse itself are required** — you only need the app installed and this one
TypeScript file loaded as a pi extension.

## Install

1. Install **AI Pulse** to `/Applications` (needed so the extension can
   launch it by name with `open -a "AI Pulse"`).
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
idle waiting for your next prompt it waits in orange. On shutdown, if AI
Pulse is no longer needed, it quits.

> **Never breaks pi:** every publish is fire-and-forget and swallowed on
> failure. If AI Pulse isn't reachable or can't be launched, pi is
> completely unaffected. No prompt text, tool inputs, or outputs are ever
> read.

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

## Open & close with pi

- **Open:** on `session_start`, if AI Pulse isn't answering `/v1/health`, the
  extension runs `open -a "AI Pulse"` and waits for the server before the
  first publish. Requires AI Pulse to be installed in `/Applications`.
- **Close:** when pi genuinely exits (`session_shutdown` reason `quit`), it
  removes the session's agent, then quits AI Pulse (graceful `osascript
  quit`) **only if this extension launched the app and the store is now
  empty**. A user-launched instance (or one started by another pi process) is
  left running. If anything else is using AI Pulse — another pi session, a
  Claude Code session, the `aipulse` CLI — it stays running. On `/reload`,
  `/new`, `/resume` or `/fork` (which keep pi alive) it removes the old agent
  but never quits, so the app isn't needlessly closed and relaunched.

This keeps AI Pulse from sitting idle and consuming resources when you're
not working with pi.

> **macOS Automation permission:** the graceful quit runs `osascript`, which
> triggers a one-time macOS Automation (Apple Events) permission prompt for
> the process hosting pi. Denial is swallowed silently (the app just stays
> open) — benign, but note that auto-quit won't work until you grant it.

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
