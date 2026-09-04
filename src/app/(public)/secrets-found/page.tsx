import type { Metadata } from "next";

import { Footer, MenuBar } from "@/features/landing";
import { SecretsFound } from "@/features/secrets";

export const metadata: Metadata = {
    title: "One of your secrets got leaked, what now?",
    description:
        "Notchlet found a leaked key in your Claude Code or Codex chats. Make a new one, swap it in, delete the old one and check for damage, in about ten minutes.",
};

// Notchlet opens this with ?rule=<betterleaks rule id>&provider=<claude-code|codex>. Awaiting searchParams is what
// makes the page dynamic, which the nonce-based CSP needs (see proxy.ts).
export default async function SecretsFoundPage(props: PageProps<"/secrets-found">) {
    const { rule, provider } = await props.searchParams;

    return (
        <main className="bg-white">
            <MenuBar light />
            <SecretsFound rule={single(rule)} provider={single(provider)} />
            <Footer />
        </main>
    );
}

function single(value: string | string[] | undefined) {
    return Array.isArray(value) ? value[0] : value;
}
