// AI Pulse ⇄ pi adapter
// -----------------------------------------------
// A pi extension that mirrors the active pi session onto the AI Pulse
// local event service, so the ambient light strip beside the Dock reflects
// what pi is doing (working, waiting for you, finished, etc.).
//
// It also **opens and closes with pi**: if AI Pulse isn't already running
// when a session starts, it launches the app; when pi actually exits, no
// other agents are using AI Pulse, and *this extension* was the one that
// launched the app, it quits it — so an instance you started yourself is
// never touched, and nothing is left running and consuming resources when
// you're not working with pi. (On /reload, /new, /resume or /fork the
// process stays alive and a new session follows, so it does not quit then.)
//
// Install: copy this file to ~/.pi/agent/extensions/aipulse-pi.ts
//   (global, all projects) — or to .pi/extensions/ inside a project for
//   project-local use — then /reload pi. No npm install needed: only the
//   extension *type* is imported; all runtime behavior uses built-ins and
//   the global fetch. For auto-launch to find it, AI Pulse should be
//   installed in /Applications (so `open -a "AI Pulse"` resolves it).
//
// It talks to the same loopback HTTP API and handshake file the `aipulse`
// CLI uses, and it is deliberately silent on any failure (AI Pulse not
// reachable, wrong token, app can't be launched) so a status light can
// never slow down or break a pi session.
//
// Event → state mapping (mirrors the Claude Code adapter's lifecycle):
//   session_start       → idle            (also launches AI Pulse if needed)
//   before_agent_start  → working          ("Working on a prompt")
//   tool_execution_start→ working          ("Running <tool>")
//     …unless ask_question → approvalRequired
//   agent_end           → completed        ("Turn finished")
//   agent_settled       → waitingForInput  ("Waiting for your input")
//   session_shutdown    → remove agent, then quit AI Pulse on real exit if
//                         this extension launched it and the store is empty
//
// Privacy: only pi-generated metadata crosses the boundary — event name and
// tool name. Prompt text, tool inputs, and outputs are never read.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

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
  sequence?: number; // strictly monotonic ms, used for ordering
  pid?: number; // AI Pulse watches this for process liveness
}

interface Handshake {
  port: number;
  token: string;
}

// ---------------------------------------------------------------------------
// Credentials: the handshake file AI Pulse writes on launch (0600). Honors
// the same AIPULSE_CONFIG / AIPULSE_PORT / AIPULSE_TOKEN env overrides the
// CLI honors. Read fresh on every request so a just-launched app's token is
// picked up.
// ---------------------------------------------------------------------------

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

// Strictly monotonic sequence: the reducer rejects `sequence == last` as a
// duplicate and `sequence < last` as outdated. pi can emit several tool
// events within one millisecond, so a raw `Date.now()` sequence would let
// an earlier transition drop a later one. Bump past the last value instead.
let lastSequence = 0;
function nextSequence(): number {
  const now = Date.now();
  lastSequence = now > lastSequence ? now : lastSequence + 1;
  return lastSequence;
}

// ---------------------------------------------------------------------------
// HTTP transport. One shared helper keeps auth, JSON, and error-swallowing
// in a single place. `null` means "don't care" (unreachable, missing token,
// or rejected) — every caller treats it as a silent no-op so a status light
// can never block, log to, or crash a pi session.
// ---------------------------------------------------------------------------

async function request(
  path: string,
  options: {
    method?: "GET" | "POST" | "DELETE";
    body?: Payload;
    auth?: boolean;
    signal?: AbortSignal;
  } = {},
): Promise<Response | null> {
  const { port, token } = endpoint();
  const auth = options.auth ?? true;
  if (auth && !token) return null; // AI Pulse not set up — nothing to reach.
  try {
    return await fetch(`http://127.0.0.1:${port}${path}`, {
      method: options.method ?? "GET",
      headers: {
        ...(options.body !== undefined ? { "Content-Type": "application/json" } : {}),
        ...(auth && token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
      signal: options.signal,
    });
  } catch {
    return null;
  }
}

async function upsert(payload: Payload): Promise<void> {
  await request("/v1/agents/upsert", { method: "POST", body: payload });
}

async function remove(agentId: string): Promise<void> {
  // The CLI percent-encodes "/" (paths live in agent IDs) so the ID stays
  // on a single route segment; encodeURIComponent does the same.
  await request(`/v1/agents/${encodeURIComponent(agentId)}`, { method: "DELETE" });
}

/** All agents currently known to AI Pulse (empty on any failure). */
async function listAgents(): Promise<unknown[]> {
  const response = await request("/v1/agents");
  if (!response?.ok) return [];
  const data = (await response.json().catch(() => null)) as { agents?: unknown[] } | null;
  return data?.agents ?? [];
}

/** True if the AI Pulse HTTP server answers /v1/health (the unauthenticated route). */
function serverUp(): Promise<boolean> {
  return request("/v1/health", { auth: false, signal: AbortSignal.timeout(1200) }).then(
    (response) => response?.ok ?? false,
  );
}

// ---------------------------------------------------------------------------
// Lifecycle: open with pi, close with pi.
// ---------------------------------------------------------------------------

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForServer(timeoutMs = 10000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await serverUp()) return;
    await sleep(200);
  }
}

/** True if the AI Pulse app process is already running. `open -a` succeeds
 *  whether it launches the app or merely activates an already-running one,
 *  so this distinguishes "we started it" from "the user already had it open"
 *  — only the former is ours to quit on shutdown. */
async function appRunning(): Promise<boolean> {
  try {
    await execFileAsync("pgrep", ["-x", "AIPulse"]);
    return true;
  } catch {
    return false;
  }
}

async function launchApp(): Promise<void> {
  try {
    await execFileAsync("open", ["-a", "AI Pulse"]);
  } catch {
    // App not installed / not launchable by name — nothing else we can do.
  }
}

async function quitApp(): Promise<void> {
  try {
    // Graceful quit so applicationWillTerminate can persist state. The first
    // call triggers a one-time macOS Automation (Apple Events) permission
    // prompt for the process hosting pi; denial is swallowed silently here
    // (the app just stays open) — benign, see pi/README.md.
    await execFileAsync("osascript", ["-e", 'quit app "AI Pulse"']);
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

/** pi's ExtensionContext is a superset of the fields we read; narrow it once here. */
function asCtx(ctx: unknown): Ctx {
  return ctx as Ctx;
}

/** One AI Pulse entry per pi session per project (mirrors the Claude adapter). */
function agentID(ctx: Ctx): string {
  const cwd = ctx.cwd || "unknown";
  const session = ctx.sessionManager?.getSessionId?.() || "unknown";
  return `pi:${cwd}:${session}`;
}

function instanceName(cwd: string): string {
  return cwd.split("/").filter(Boolean).pop() || cwd;
}

function makePayload(ctx: Ctx, state: AgentState, message: string): Payload {
  const cwd = ctx.cwd || "unknown";
  const instance = instanceName(cwd);
  return {
    version: 1,
    agent: { id: agentID(ctx), name: "pi", provider: "pi", instance, icon: "terminal" },
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

/** Build and publish one status update. */
function publish(ctx: Ctx, state: AgentState, message: string): Promise<void> {
  return upsert(makePayload(ctx, state, message));
}

// ---------------------------------------------------------------------------
// Extension entry point.
// ---------------------------------------------------------------------------

// True once this pi process has launched AI Pulse itself. Only the process
// that started the app quits it on shutdown; a user-launched instance (or
// one started by another pi process, which owns its own flag) is left alone.
let launchedApp = false;

export default function (pi: ExtensionAPI): void {
  pi.on("session_start", async (event, ctx) => {
    // Open with pi: bring AI Pulse up if it isn't already, then wait for it
    // to finish starting before the first publish. Remember whether *we*
    // launched it, so shutdown only quits an app this extension started.
    if (!(await serverUp())) {
      if (await appRunning()) {
        // Already up but still booting — the user (or a sibling pi process)
        // started it, so it isn't ours to quit. Just give the server a moment.
        await waitForServer();
      } else {
        // Not running: bringing it up is on us, so it's ours to quit later.
        await launchApp();
        launchedApp = true;
      }
    }
    await publish(
      asCtx(ctx),
      "idle",
      event.reason === "resume" ? "Session resumed" : "Session started",
    );
  });

  pi.on("before_agent_start", (_event, ctx) => {
    publish(asCtx(ctx), "working", "Working on a prompt");
  });

  pi.on("tool_execution_start", (event, ctx) => {
    // ask_question means pi is blocked waiting on a yes/no answer from you.
    const approval = event.toolName === "ask_question";
    publish(
      asCtx(ctx),
      approval ? "approvalRequired" : "working",
      approval ? "Waiting for your answer" : `Running ${event.toolName}`,
    );
  });

  pi.on("agent_end", (_event, ctx) => {
    publish(asCtx(ctx), "completed", "Turn finished");
  });

  pi.on("agent_settled", (_event, ctx) => {
    // The whole run (including retries/compaction) is done; pi is idle,
    // waiting for your next input.
    publish(asCtx(ctx), "waitingForInput", "Waiting for your input");
  });

  pi.on("session_shutdown", async (event, ctx) => {
    const context = asCtx(ctx);
    await remove(agentID(context));
    // Close with pi: only quit the app when pi is genuinely terminating, this
    // extension is the one that launched it, and nothing else is using AI
    // Pulse (another pi session, Claude Code, or the CLI). A user-launched
    // instance is left alone. /reload, /new, /resume and /fork keep the
    // process alive and are followed by a fresh session_start, so quitting
    // then would just flash the app. The PID we sent also means AI Pulse
    // self-cleans if we ever die without a graceful shutdown.
    if (event.reason === "quit" && launchedApp && (await listAgents()).length === 0) {
      await quitApp();
    }
  });
}
