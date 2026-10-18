import type { MetadataRoute } from "next";

import { competitors } from "@/features/compare";
import { providers } from "@/features/providers";
import { siteUrl } from "@/lib/site";

const page = (path: string) => new URL(path, siteUrl).href;

export default function sitemap(): MetadataRoute.Sitemap {
    return [
        { url: page("/"), changeFrequency: "weekly", priority: 1 },
        ...providers.map((provider) => ({ url: page(`/${provider.slug}`), priority: 0.8 })),
        ...competitors.map((competitor) => ({ url: page(`/vs/${competitor.slug}`), priority: 0.6 })),
        { url: page("/secrets-found"), changeFrequency: "monthly", priority: 0.5 },
    ];
}
