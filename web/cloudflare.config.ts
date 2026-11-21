// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Zeist Chess web Worker. Nothing here creates or changes a Cloudflare resource until someone runs `cf deploy`;
// web/README.md says exactly what a deploy needs.
//
//   ZC_BASE   the path the pages are served under. Defaults to "/chess/vs/". Must match the one scripts/assets.mjs built.
//   ZC_HOME   where unknown addresses are sent: Zeist's Chess, "/chess".
//   ZC_ROUTE  the route to publish to, such as "zeist.gg/chess/vs*" (no slash, so the bare /chess/vs reaches the Worker too). Without it, a deploy publishes no route.
//   ZC_ZONE   the zone the route belongs to, such as "zeist.gg".
import { bindings, defineConfig, triggers } from "cf/config";
import * as entrypoint from "./src/worker.js" with { type: "cf-worker" };

const BASE = process.env.ZC_BASE || "/chess/vs/";
const HOME = process.env.ZC_HOME || "/chess";
const ROUTE = process.env.ZC_ROUTE;
const ZONE = process.env.ZC_ZONE;

export default defineConfig(({ mode }) => ({
	worker: {
		name: "zeist-chess",
		compatibilityDate: "2026-09-25",
		entrypoint,
		env: {
			ASSETS: bindings.assets(),
			BASE: bindings.text(BASE),
			HOME: bindings.text(HOME),
			// Engine packs, the bucket behind engines.zei.st. Read only.
			ENGINES: bindings.r2({ name: "zeist-chess-engines" }),
			// Local development has an empty bucket: packs come from the public server instead.
			...(mode === "production" ? {} : { ENGINES_ORIGIN: bindings.text("https://engines.zei.st/") }),
		},
		// Static first: the pages, engines.json and the app's files are assets (web/site/, laid out at BASE, headers in
		// site/_headers), served without running the Worker. It runs only when no asset matches: <base>engines/ (packs,
		// until engines.zei.st sends CORS headers) and unknown addresses, which it sends to HOME.
		assets: { runWorkerFirst: false, htmlHandling: "auto-trailing-slash", notFoundHandling: "none" },
		workersDev: false,
		previewUrls: false,
		observability: { enabled: true },
		...(ROUTE ? { triggers: [triggers.fetch({ pattern: ROUTE, ...(ZONE ? { zone: ZONE } : {}) })] } : {}),
	},
}));
