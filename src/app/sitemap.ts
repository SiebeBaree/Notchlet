import type { MetadataRoute } from "next";

import { siteUrl } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
    return [
        { url: new URL("/", siteUrl).href, changeFrequency: "weekly", priority: 1 },
        { url: new URL("/secrets-found", siteUrl).href, changeFrequency: "monthly", priority: 0.5 },
    ];
}
