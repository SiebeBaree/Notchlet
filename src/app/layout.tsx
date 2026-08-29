import type { Metadata, Viewport } from "next";
import { Geist } from "next/font/google";
import { headers } from "next/headers";

import "./globals.css";

import { Toaster } from "@/components/ui/sonner";
import { siteDescription, siteName, siteUrl } from "@/lib/site";
import { cn } from "@/lib/utils";

import { Providers } from "./providers";

const geist = Geist({ subsets: ["latin"], variable: "--font-sans" });

export const metadata: Metadata = {
    metadataBase: siteUrl,
    title: { default: siteName, template: `%s · ${siteName}` },
    description: siteDescription,
    alternates: { canonical: "./" },
    openGraph: {
        type: "website",
        siteName,
        title: siteName,
        description: siteDescription,
        url: "./",
    },
    twitter: { card: "summary" },
};

export const viewport: Viewport = {
    themeColor: "#ffffff",
};

export default async function RootLayout({ children }: LayoutProps<"/">) {
    const nonce = (await headers()).get("x-nonce") ?? undefined;
    const jsonLd = JSON.stringify({
        "@context": "https://schema.org",
        "@type": "WebSite",
        name: siteName,
        description: siteDescription,
        url: siteUrl.href,
    }).replaceAll("<", "\\u003c");

    return (
        <html lang="en" className={cn("font-sans", geist.variable)}>
            <body className="min-h-dvh antialiased">
                <Providers>{children}</Providers>
                <Toaster />
                <script type="application/ld+json" nonce={nonce} dangerouslySetInnerHTML={{ __html: jsonLd }} />
            </body>
        </html>
    );
}
