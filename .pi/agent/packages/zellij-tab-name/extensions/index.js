/**
 * pi-zellij-tab-name — sync the pi session name to the current zellij tab.
 *
 * Renames the zellij tab ONLY when the session name is explicitly set
 * (/name command, RPC, pi.setSessionName()) via the `session_info_changed`
 * event. Never renames on session start/resume/launch (`pi --name` included)
 * and never invents a name — earlier versions auto-renamed to the cwd
 * basename, which kept naming tabs "pc"; fixed 2026-08-31 per user rule:
 * "never rename my zellij tabs unless I triggered it". No-op outside zellij.
 */

import { execFile } from "node:child_process";
import { appendFileSync } from "node:fs";

const DEBUG = process.env.ZTN_DEBUG === "1";
const log = (...args) => {
	if (DEBUG) {
		try {
			appendFileSync("/tmp/ztn-debug.log", args.join(" ") + "\n");
		} catch {}
	}
};


export default function (pi) {
	log("extension loaded, pid", process.pid, "ZELLIJ_SESSION_NAME:", process.env.ZELLIJ_SESSION_NAME);

	// Resolve THIS session's own tab ID from its pane ID — never rely on
	// focus. A bare `zellij action rename-tab` renames whatever tab the
	// user happens to have focused, which is wrong the moment they click
	// elsewhere. Stable IDs only (list-panes -j gives each pane's tab_id).
	const resolveOwnTabId = (cb) => {
		execFile("zellij", ["action", "list-panes", "-j"], (err, stdout) => {
			if (err) return cb(err);
			try {
				const panes = JSON.parse(stdout);
				const me = panes.find((p) => String(p.id) === String(process.env.ZELLIJ_PANE_ID));
				cb(null, me ? String(me.tab_id) : null);
			} catch (e) {
				cb(e);
			}
		});
	};

	const rename = (name) => {
		log("rename called with:", JSON.stringify(name));
		if (!process.env.ZELLIJ_PANE_ID) {
			log("skipped: not inside zellij");
			return;
		}
		if (!name) return;
		resolveOwnTabId((err, tabId) => {
			if (err || !tabId) {
				log("tab-id resolve failed:", err?.message ?? null, "tabId:", tabId);
				return;
			}
			log("executing zellij action rename-tab", name, "--tab-id", tabId);
			execFile("zellij", ["action", "rename-tab", name, "--tab-id", tabId], (err2, _stdout, stderr) => {
				if (err2 || stderr) log("rename result err:", err2?.message ?? null, "stderr:", String(stderr));
				else log("rename ok (tab", tabId + ")");
			});
		});
	};

	// Intentionally NO session_start handler: session launch/resume must not
	// rename tabs — only an explicit /name (session_info_changed) may.
	pi.on("session_info_changed", async (event) => {
		log("session_info_changed:", JSON.stringify(event));
		rename(event.name);
	});
}