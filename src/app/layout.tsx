import type { Metadata, Viewport } from "next";
import { Crimson_Pro, Geist, Geist_Mono } from "next/font/google";
import { headers } from "next/headers";

import "./globals.css";

import { Toaster } from "@/components/ui/sonner";
import { siteDescription, siteName, siteTitle, siteUrl } from "@/lib/site";
import { cn } from "@/lib/utils";

import { Providers } from "./providers";

const geist = Geist({ subsets: ["latin"], variable: "--font-sans" });
const geistMono = Geist_Mono({ subsets: ["latin"], variable: "--font-mono" });
const crimsonPro = Crimson_Pro({ subsets: ["latin"], variable: "--font-display" });

export const metadata: Metadata = {
    metadataBase: siteUrl,
    title: { default: siteName, template: `%s · ${siteName}` },
    description: siteDescription,
    alternates: { canonical: "./" },
    openGraph: {
        type: "website",
        siteName,
        title: siteTitle,
        description: siteDescription,
        url: "./",
        images: [{ url: "/og.png", width: 2400, height: 1260, alt: "The Notchlet notch showing plan usage rings." }],
    },
    // Launch traffic arrives from X, where summary renders a thumbnail and summary_large_image renders the card.
    twitter: {
        card: "summary_large_image",
        title: siteTitle,
        description: siteDescription,
        images: ["/og.png"],
    },
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
        <html lang="en" className={cn("font-sans", geist.variable, geistMono.variable, crimsonPro.variable)}>
            <body className="min-h-dvh antialiased">
                <Providers>{children}</Providers>
                <Toaster />
                <script type="application/ld+json" nonce={nonce} dangerouslySetInnerHTML={{ __html: jsonLd }} />
            </body>
        </html>
    );
}
