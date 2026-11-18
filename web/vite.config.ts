// SPDX-License-Identifier: AGPL-3.0-or-later
// The dev server and build for the Worker (cf dev, cf deploy). The app in public/ is served as it is: no bundling.
import { cloudflare } from "@cloudflare/vite-plugin";
import { defineConfig } from "vite";

export default defineConfig({
	plugins: [cloudflare()],
});
