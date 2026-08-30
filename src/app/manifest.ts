import type { MetadataRoute } from "next";

import { siteDescription, siteName } from "@/lib/site";

// Next serves this at /manifest.webmanifest and adds the link tag. The icons live in public/ because a manifest
// has to point at stable URLs.
export default function manifest(): MetadataRoute.Manifest {
    return {
        name: siteName,
        short_name: siteName,
        description: siteDescription,
        start_url: "/",
        display: "standalone",
        background_color: "#ffffff",
        theme_color: "#ffffff",
        icons: [
            { src: "/icon-192.png", sizes: "192x192", type: "image/png" },
            { src: "/icon-512.png", sizes: "512x512", type: "image/png" },
        ],
    };
}
