/**
 * PATH for pi's own process
 *
 * pi only prepends its bin dir (`~/.pi/agent/bin`) to the environment of *tool*
 * subprocesses (getShellEnv() in pi core returns a copy of process.env with the
 * bin dir added). `process.env.PATH` itself is never touched.
 *
 * Anything that spawns a binary directly from pi's process therefore cannot see
 * CLIs living in `~/.pi/agent/bin` or `~/.local/bin` — e.g. the Cursor ACP
 * provider's `spawnSync("cursor-agent", ["--version"])`, which fails with:
 *
 *   Failed to login to Cursor (ACP): Cursor Agent CLI was not found.
 *
 * This is invisible from the bash tool, because that tool *does* get the patched
 * env — so `which cursor-agent` succeeds while the provider still fails.
 *
 * Runs at extension load, i.e. before providers resolve or spawn their binaries.
 * Idempotent, and a no-op for dirs that are already present or missing.
 */

import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

function prependToProcessPath(): void {
	const candidates = [
		process.env.PI_AGENT_DIR ? join(process.env.PI_AGENT_DIR, "bin") : join(homedir(), ".pi", "agent", "bin"),
		join(homedir(), ".local", "bin"),
	];

	const key = Object.keys(process.env).find((k) => k.toLowerCase() === "path") ?? "PATH";
	const entries = (process.env[key] ?? "").split(delimiter).filter(Boolean);
	const missing = candidates.filter((dir) => existsSync(dir) && !entries.includes(dir));

	if (missing.length > 0) {
		process.env[key] = [...missing, ...entries].join(delimiter);
	}
}

prependToProcessPath();

export default function (): void {
	prependToProcessPath();
}
