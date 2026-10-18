import { headers } from "next/headers";

export type FaqItem = { q: string; a: string };

// One JSON-LD block. Reads the per-request CSP nonce, so it only renders from server components.
export async function JsonLd({ data }: { data: Record<string, unknown> }) {
    const nonce = (await headers()).get("x-nonce") ?? undefined;
    // "<" escaped so no string in the data can close the script tag.
    const json = JSON.stringify({ "@context": "https://schema.org", ...data }).replaceAll("<", "\\u003c");
    return <script type="application/ld+json" nonce={nonce} dangerouslySetInnerHTML={{ __html: json }} />;
}

// The FAQPage schema for a list of questions, so search results can show them under the page.
export function faqPage(items: FaqItem[]) {
    return {
        "@type": "FAQPage",
        mainEntity: items.map((item) => ({
            "@type": "Question",
            name: item.q,
            acceptedAnswer: { "@type": "Answer", text: item.a },
        })),
    };
}
