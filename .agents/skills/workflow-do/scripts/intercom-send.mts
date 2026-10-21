#!/usr/bin/env node
// intercom-send.mjs — one-shot intercom sender for workflow-do (host notifications).
// Usage: node intercom-send.mts <target-session-name> "<message>"
// Since v7 the orchestrator (workflow-do.ts) imports IntercomClient directly and
// no longer shells out to this script, but it remains usable as a manual CLI.
//
// Registers a transient session with the pi-intercom broker, sends the message,
// disconnects. Imported live from the pi-intercom package mounted into the cage,
// so it works both on the host and inside cages. Never throws on missing broker —
// callers treat notification failures as non-fatal.

import { IntercomClient } from
  "$HOME/.pi/agent/npm/node_modules/pi-intercom/broker/client.ts";

const [to, ...rest] = process.argv.slice(2);
const text = rest.join(" ");
if (!to || !text) {
  console.error("usage: intercom-send.mts <target-session-name> \"<message>\"");
  process.exit(2);
}

const client = new IntercomClient();
try {
  await client.connect(
    { name: "workflow-do-script", cwd: process.cwd(), model: "script", pid: process.pid, startedAt: Date.now(), lastActivity: Date.now() },
  );
  const result = await client.send(to, { text });
  if (!result.delivered) {
    console.error(`intercom: not delivered (${result.reason ?? "unknown"})`);
    process.exitCode = 1;
  }
} catch (err) {
  console.error(`intercom: send failed: ${err?.message ?? err}`);
  process.exitCode = 1;
} finally {
  await client.disconnect().catch(() => {});
}