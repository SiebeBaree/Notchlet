import type { Metadata, Viewport } from "next";
import { Crimson_Pro, Geist, Geist_Mono } from "next/font/google";

import "./globals.css";

import { JsonLd } from "@/components/json-ld";
import { Toaster } from "@/components/ui/sonner";
import { siteDescription, siteName, siteTitle, siteUrl } from "@/lib/site";
import { cn } from "@/lib/utils";

import { Providers } from "./providers";

const geist = Geist({ subsets: ["latin"], variable: "--font-sans" });
const geistMono = Geist_Mono({ subsets: ["latin"], variable: "--font-mono" });
const crimsonPro = Crimson_Pro({ subsets: ["latin"], variable: "--font-display" });

export const metadata: Metadata = {
    metadataBase: siteUrl,
    title: { default: siteTitle, template: `%s · ${siteName}` },
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

export default function RootLayout({ children }: LayoutProps<"/">) {
    return (
        <html lang="en" className={cn("font-sans", geist.variable, geistMono.variable, crimsonPro.variable)}>
            <body className="min-h-dvh antialiased">
                <Providers>{children}</Providers>
                <Toaster />
                <JsonLd
                    data={{ "@type": "WebSite", name: siteName, description: siteDescription, url: siteUrl.href }}
                />
            </body>
        </html>
    );
}
