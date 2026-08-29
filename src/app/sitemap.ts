import type { MetadataRoute } from "next";

import { siteUrl } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
    return [
        { url: new URL("/", siteUrl).href, changeFrequency: "monthly", priority: 1 },
        { url: new URL("/todos", siteUrl).href, changeFrequency: "daily", priority: 0.8 },
    ];
}
