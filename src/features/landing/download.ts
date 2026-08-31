import "server-only";
import { after } from "next/server";
import { z } from "zod";

import { logger } from "@/lib/logger";

import { githubUrl } from "./links";

const latestReleaseApi = "https://api.github.com/repos/SiebeBaree/Notchlet/releases/latest";
const releasesUrl = `${githubUrl}/releases/latest`;

const releaseSchema = z.object({
    assets: z.array(z.object({ name: z.string(), browser_download_url: z.url() })),
});

/**
 * The .dmg of the newest GitHub release. Resolved at request time and cached for an hour, so shipping a release puts
 * it on the site without a deploy and a burst of downloads cannot exhaust the unauthenticated API rate limit.
 *
 * When GitHub cannot be reached this falls back to the releases page: one extra click beats a dead link.
 */
export async function latestDownloadUrl() {
    try {
        const response = await fetch(latestReleaseApi, {
            headers: { Accept: "application/vnd.github+json" },
            next: { revalidate: 3600 },
        });
        if (!response.ok) throw new Error(`GitHub returned ${response.status}`);

        const { assets } = releaseSchema.parse(await response.json());
        const dmg = assets.find((asset) => asset.name.endsWith(".dmg"));
        if (!dmg) throw new Error("Latest release has no .dmg asset");

        return dmg.browser_download_url;
    } catch (error) {
        logger.warn("landing.download", {
            ok: false,
            error: error instanceof Error ? error.message : String(error),
        });
        after(() => logger.flush());
        return releasesUrl;
    }
}
