/**
 * Cage Indicator Extension
 *
 * Shows a persistent amber badge in the pi footer when the session runs
 * inside a cage (the docker sandbox launched by cage() in ~/.bashrc).
 *
 * Detection: WORKFLOW_CONTAINER_ID is passed by cage() via `docker exec -e`
 * and is never set on the host. Fallback: /.dockerenv exists in any docker
 * container. Host sessions: no badge (zero false positives).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		const cageId = process.env.WORKFLOW_CONTAINER_ID;
		if (cageId) {
			ctx.ui.setStatus("cage", ctx.ui.theme.fg("warning", `⛓ ${cageId}`));
		} else if (process.platform === "linux") {
			// fallback: manually exec'd docker shells
			const fs = await import("fs");
			if (fs.existsSync("/.dockerenv")) {
				ctx.ui.setStatus("cage", ctx.ui.theme.fg("warning", "⛓ container"));
			}
		}
	});
}