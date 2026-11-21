// SPDX-License-Identifier: AGPL-3.0-or-later
// The dev server and build for the Worker (cf dev, cf deploy). The site in site/ (from public/ and pages/, by scripts/assets.mjs) is served as it is: no bundling.
import { cloudflare } from "@cloudflare/vite-plugin";
import { defineConfig } from "vite";

export default defineConfig({
	// The site scripts/assets.mjs builds, laid out at the base path, with its _headers.
	publicDir: "site",
	plugins: [cloudflare()],
});
