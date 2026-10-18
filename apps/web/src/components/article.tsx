import { Plus } from "lucide-react";
import type { ReactNode } from "react";

import { type FaqItem, faqPage, JsonLd } from "./json-ld";

export function ArticleHeader({ title, children }: { title: string; children: ReactNode }) {
    return (
        <header className="relative overflow-hidden px-6 pt-32 pb-14 sm:pt-40 sm:pb-16">
            <div
                aria-hidden
                className="absolute inset-0 bg-[radial-gradient(60%_60%_at_50%_0%,#efeafd,transparent_70%)]"
            />
            <div className="relative mx-auto max-w-3xl">
                <h1 className="text-[36px] leading-[1.12] font-semibold tracking-[-0.035em] text-balance text-ink sm:text-[48px]">
                    {title}
                </h1>
                <div className="mt-6 max-w-2xl text-[15px] leading-relaxed text-ink-3">{children}</div>
            </div>
        </header>
    );
}

export function Section({ title, sub, children }: { title: string; sub?: string; children: ReactNode }) {
    return (
        <section className="border-t border-line px-6 py-14 sm:py-16">
            <div className="mx-auto max-w-3xl">
                <h2 className="text-[24px] leading-tight font-semibold tracking-tight text-ink sm:text-[28px]">
                    {title}
                </h2>
                {sub && <p className="mt-3 text-sm leading-relaxed text-ink-3">{sub}</p>}
                <div className="mt-7 flex flex-col gap-5 text-[15px] leading-relaxed text-ink-2">{children}</div>
            </div>
        </section>
    );
}

export function Code({ children }: { children: ReactNode }) {
    return (
        <code className="rounded-sm bg-brand-soft/70 px-1.5 py-0.5 font-mono text-[13px] break-words text-ink">
            {children}
        </code>
    );
}

// Keep visible answers and FAQPage structured data in sync.
export function Faq({ items }: { items: FaqItem[] }) {
    return (
        <div>
            <JsonLd data={faqPage(items)} />
            {items.map((item, index) => (
                <details key={item.q} open={index === 0} className="group border-b border-line py-4 first:pt-0">
                    <summary className="flex cursor-pointer list-none items-center justify-between gap-5 text-[13px] font-medium text-ink marker:content-none [&::-webkit-details-marker]:hidden">
                        {item.q}
                        <Plus aria-hidden className="size-4 shrink-0 text-ink-3 group-open:rotate-45" />
                    </summary>
                    <p className="mt-3 max-w-2xl text-[13px] leading-relaxed text-ink-3">{item.a}</p>
                </details>
            ))}
        </div>
    );
}
