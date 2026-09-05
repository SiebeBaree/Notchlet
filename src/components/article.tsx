import type { ReactNode } from "react";

import { type FaqItem, faqPage, JsonLd } from "./json-ld";

// A two-tone heading over a reading column. Every prose page on the site is a stack of these.
export function Section({ title, sub, children }: { title: string; sub: string; children: ReactNode }) {
    return (
        <section className="border-t border-line px-6 py-20">
            <div className="mx-auto max-w-3xl">
                <h2 className="text-[26px] leading-[1.25] font-semibold tracking-tight text-ink sm:text-[30px]">
                    {title} <span className="text-ink-3">{sub}</span>
                </h2>
                <div className="mt-10 flex flex-col gap-5 text-[15px] leading-relaxed text-ink-2">{children}</div>
            </div>
        </section>
    );
}

export function Code({ children }: { children: ReactNode }) {
    return (
        <code className="rounded-sm bg-brand-soft/70 px-1.5 py-0.5 font-mono text-[13px] whitespace-nowrap text-ink">
            {children}
        </code>
    );
}

// Questions with their FAQPage schema, so what the reader sees and what search engines index is one list.
export function Faq({ items }: { items: FaqItem[] }) {
    return (
        <>
            <JsonLd data={faqPage(items)} />
            <dl className="grid gap-x-12 gap-y-10 sm:grid-cols-2">
                {items.map((item) => (
                    <div key={item.q}>
                        <dt className="text-[15px] font-semibold tracking-tight text-ink">{item.q}</dt>
                        <dd className="mt-2 text-sm leading-relaxed text-ink-3">{item.a}</dd>
                    </div>
                ))}
            </dl>
        </>
    );
}
