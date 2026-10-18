import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { connection } from "next/server";

import { Cta, Footer, MenuBar } from "@/features/landing";
import { ProviderPage, providerFor } from "@/features/providers";

export async function generateMetadata(props: PageProps<"/[provider]">): Promise<Metadata> {
    const provider = providerFor((await props.params).provider);
    return provider ? { title: provider.title, description: provider.description } : {};
}

// One page per agent Notchlet tracks: /claude-code, /codex, /cursor and /opencode. Anything else is a 404.
export default async function ProviderRoute(props: PageProps<"/[provider]">) {
    const provider = providerFor((await props.params).provider);
    if (!provider) notFound();
    // Nonce-based CSP requires dynamic rendering (see proxy.ts).
    await connection();

    return (
        <main className="bg-white">
            <MenuBar light />
            <ProviderPage provider={provider} />
            <Cta />
            <Footer />
        </main>
    );
}
