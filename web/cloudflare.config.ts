// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Zeist Chess web Worker. Nothing here creates or changes a Cloudflare resource until someone runs `cf deploy`;
// web/README.md says exactly what a deploy needs.
//
//   ZC_BASE   the path the app is served under, such as "/chess/engines/". Defaults to "/".
//   ZC_ROUTE  the route to publish to, such as "zeist.gg/chess/engines*". Without it, a deploy publishes no route.
//   ZC_ZONE   the zone the route belongs to, such as "zeist.gg".
import { bindings, defineConfig, triggers } from "cf/config";
import * as entrypoint from "./src/worker.js" with { type: "cf-worker" };

const BASE = process.env.ZC_BASE || "/";
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
			// Engine packs, the bucket behind engines.zei.st. Read only.
			ENGINES: bindings.r2({ name: "zeist-chess-engines" }),
			// Local development has an empty bucket: packs come from the public server instead.
			...(mode === "production" ? {} : { ENGINES_ORIGIN: bindings.text("https://engines.zei.st/") }),
		},
		// Every request goes through the Worker, which serves only what is under BASE.
		assets: { runWorkerFirst: true, htmlHandling: "auto-trailing-slash", notFoundHandling: "none" },
		workersDev: false,
		previewUrls: false,
		observability: { enabled: true },
		...(ROUTE ? { triggers: [triggers.fetch({ pattern: ROUTE, ...(ZONE ? { zone: ZONE } : {}) })] } : {}),
	},
}));
