import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { connection } from "next/server";

import { ComparePage, competitorFor } from "@/features/compare";
import { Cta, Footer, MenuBar } from "@/features/landing";

export async function generateMetadata(props: PageProps<"/vs/[competitor]">): Promise<Metadata> {
    const competitor = competitorFor((await props.params).competitor);
    return competitor ? { title: competitor.title, description: competitor.description } : {};
}

// Notchlet against one other usage tracker, at /vs/<slug>. Unknown slugs are a 404.
export default async function CompareRoute(props: PageProps<"/vs/[competitor]">) {
    const competitor = competitorFor((await props.params).competitor);
    if (!competitor) notFound();
    // Nonce-based CSP requires dynamic rendering (see proxy.ts).
    await connection();

    return (
        <main className="bg-white">
            <MenuBar light />
            <ComparePage competitor={competitor} />
            <Cta />
            <Footer />
        </main>
    );
}
