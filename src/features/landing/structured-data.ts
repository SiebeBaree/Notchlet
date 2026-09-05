import "server-only";
import { siteDescription, siteName, siteUrl } from "@/lib/site";

import { githubUrl } from "./links";

// What search engines and answer engines are told the product is. The download URL resolves to the newest release.
export const softwareApplication = {
    "@type": "SoftwareApplication",
    name: siteName,
    description: siteDescription,
    url: siteUrl.href,
    image: new URL("/og.png", siteUrl).href,
    downloadUrl: new URL("/download", siteUrl).href,
    sameAs: [githubUrl],
    applicationCategory: "DeveloperApplication",
    operatingSystem: "macOS 14 or later",
    license: "https://opensource.org/license/mit",
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
};
