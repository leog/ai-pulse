// AI Pulse ⇄ pi adapter
// -----------------------------------------------
// A pi extension that mirrors the active pi session onto the AI Pulse
// local event service, so the ambient light strip beside the Dock reflects
// what pi is doing (working, waiting for you, finished, etc.).
//
// Install: copy this file to ~/.pi/agent/extensions/aipulse-pi.ts
//   (global, all projects) — or to .pi/extensions/ inside a project for
//   project-local use — then /reload pi. No npm install needed: only the
//   extension *type* is imported; all runtime behavior uses built-ins and
//   the global fetch.
//
// It talks to the same loopback HTTP API and handshake file the `aipulse`
// CLI uses, and it is deliberately silent on any failure (AI Pulse not
// running, unreachable, wrong token) so a status light can never slow down
// or break a pi session.
//
// Event → state mapping (mirrors the Claude Code adapter's lifecycle):
//   session_start       → idle
//   before_agent_start  → working          ("Working on a prompt")
//   tool_execution_start→ working          ("Running <tool>")
//     …unless ask_question → approvalRequired
//   agent_end           → completed        ("Turn finished")
//   agent_settled       → waitingForInput  ("Waiting for your input")
//   session_shutdown    → remove agent
//
// Privacy: only pi-generated metadata crosses the boundary — event name and
// tool name. Prompt text, tool inputs, and outputs are never read.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ---------------------------------------------------------------------------
// AI Pulse wire model (subset of AgentEventPayload / AgentState).
// ---------------------------------------------------------------------------

type AgentState =
  | "idle"
  | "working"
  | "waitingForInput"
  | "approvalRequired"
  | "completed"
  | "failed"
  | "disconnected"
  | "unknown";

interface Payload {
  version: number;
  agent: {
    id: string;
    name: string;
    provider: string;
    instance?: string;
    icon?: string;
  };
  state: AgentState;
  message?: string;
  project?: { name?: string; path?: string };
  action?: { type: string; bundleIdentifier: string };
  occurredAt: string; // ISO-8601; the server decodes with .iso8601
  sequence?: number; // monotonic-ish ms timestamp, used for ordering
  pid?: number; // AI Pulse watches this for process liveness
}

interface Handshake {
  port: number;
  token: string;
}

// ---------------------------------------------------------------------------
// Credentials: the handshake file AI Pulse writes on launch (0600). Honors
// the same AIPULSE_CONFIG / AIPULSE_PORT / AIPULSE_TOKEN env overrides the
// CLI honors.
// ---------------------------------------------------------------------------

// Strictly monotonic sequence: the reducer rejects `sequence == last` as a
// duplicate and `sequence < last` as outdated. pi can emit several tool
// events within one millisecond, so a raw `Date.now()` sequence would let
// an earlier transition drop a later one. Bump past the last value instead.
let lastSequence = { value: 0 };
function nextSequence(): number {
  const now = Date.now();
  lastSequence.value = now > lastSequence.value ? now : lastSequence.value + 1;
  return lastSequence.value;
}

const HANDSHAKE_PATH =
  process.env.AIPULSE_CONFIG ??
  join(homedir(), "Library", "Application Support", "AIPulse", "cli.json");

function loadHandshake(): Handshake | null {
  try {
    return JSON.parse(readFileSync(HANDSHAKE_PATH, "utf8")) as Handshake;
  } catch {
    return null;
  }
}

function endpoint(): { port: number; token: string | undefined } {
  const handshake = loadHandshake();
  const port = Number(process.env.AIPULSE_PORT) || handshake?.port || 7455;
  const token = process.env.AIPULSE_TOKEN || handshake?.token;
  return { port, token };
}

// ---------------------------------------------------------------------------
// Publish helpers. Every call is fire-and-forget: a status light must never
// block, log to, or crash a pi session.
// ---------------------------------------------------------------------------

async function upsert(payload: Payload): Promise<void> {
  const { port, token } = endpoint();
  if (!token) return; // AI Pulse never launched — nothing to report to.
  try {
    await fetch(`http://127.0.0.1:${port}/v1/agents/upsert`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(payload),
    });
  } catch {
    // AI Pulse not running or unreachable — ignore.
  }
}

async function remove(agentId: string): Promise<void> {
  const { port, token } = endpoint();
  if (!token) return;
  try {
    // The CLI percent-encodes "/" (paths live in agent IDs) so the ID stays
    // on a single route segment; encodeURIComponent does the same.
    await fetch(`http://127.0.0.1:${port}/v1/agents/${encodeURIComponent(agentId)}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    });
  } catch {
    // Ignore.
  }
}

// ---------------------------------------------------------------------------
// Identity + payload construction.
// ---------------------------------------------------------------------------

type Ctx = {
  cwd: string;
  sessionManager?: { getSessionId?: () => string };
};

/** One AI Pulse entry per pi session per project (mirrors the Claude adapter). */
function agentID(ctx: Ctx): string {
  const cwd = ctx.cwd || "unknown";
  const session = ctx.sessionManager?.getSessionId?.() || "unknown";
  return `pi:${cwd}:${session}`;
}

function instanceName(cwd: string): string {
  return cwd.split("/").filter(Boolean).pop() || cwd;
}

function makePayload(
  ctx: Ctx,
  state: AgentState,
  message: string,
): Payload {
  const cwd = ctx.cwd || "unknown";
  const instance = instanceName(cwd);
  return {
    version: 1,
    agent: {
      id: agentID(ctx),
      name: "pi",
      provider: "pi",
      instance,
      icon: "terminal",
    },
    state,
    message,
    project: { name: instance, path: cwd },
    // If pi was launched from a GUI app, offer an action that brings that
    // app forward (matches the Claude adapter). Terminal-launched pi omits it.
    ...(process.env.__CFBundleIdentifier
      ? { action: { type: "activateApplication", bundleIdentifier: process.env.__CFBundleIdentifier } }
      : {}),
    occurredAt: new Date().toISOString(),
    sequence: nextSequence(),
    pid: process.pid,
  };
}

// ---------------------------------------------------------------------------
// Extension entry point.
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI): void {
  pi.on("session_start", (event, ctx) => {
    upsert(
      makePayload(
        ctx as unknown as Ctx,
        "idle",
        event.reason === "resume" ? "Session resumed" : "Session started",
      ),
    );
  });

  pi.on("before_agent_start", (_event, ctx) => {
    upsert(makePayload(ctx as unknown as Ctx, "working", "Working on a prompt"));
  });

  pi.on("tool_execution_start", (event, ctx) => {
    if (event.toolName === "ask_question") {
      // pi is blocked waiting on a yes/no answer from you.
      upsert(makePayload(ctx as unknown as Ctx, "approvalRequired", "Waiting for your answer"));
    } else {
      upsert(makePayload(ctx as unknown as Ctx, "working", `Running ${event.toolName}`));
    }
  });

  pi.on("agent_end", (_event, ctx) => {
    upsert(makePayload(ctx as unknown as Ctx, "completed", "Turn finished"));
  });

  pi.on("agent_settled", (_event, ctx) => {
    // The whole run (including retries/compaction) is done; pi is idle,
    // waiting for your next input.
    upsert(makePayload(ctx as unknown as Ctx, "waitingForInput", "Waiting for your input"));
  });

  pi.on("session_shutdown", (_event, ctx) => {
    remove(agentID(ctx as unknown as Ctx));
  });
}
