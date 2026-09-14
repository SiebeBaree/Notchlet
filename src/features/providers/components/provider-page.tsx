import { ArrowUpRight } from "lucide-react";

import { ArticleHeader, Code, Faq, Section } from "@/components/article";

import type { Provider } from "../providers";

export function ProviderPage({ provider }: { provider: Provider }) {
    const { builtIn } = provider;
    return (
        <article className="mx-auto max-w-7xl border-x border-line bg-white sm:mx-6 xl:mx-auto">
            <ArticleHeader title={provider.heading}>
                <p>{provider.intro}</p>
            </ArticleHeader>

            <Section title={`Check in ${provider.name}`}>
                {"command" in builtIn ? (
                    <p>
                        Run <Code>{builtIn.command}</Code> {builtIn.where}.
                    </p>
                ) : (
                    <a
                        href={builtIn.link.href}
                        target="_blank"
                        rel="noreferrer"
                        className="inline-flex w-fit items-center gap-1.5 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-ink-2"
                    >
                        {builtIn.link.label}
                        <ArrowUpRight aria-hidden className="size-4" />
                    </a>
                )}
                <p>{builtIn.body}</p>
            </Section>

            <Section title="Check in Notchlet">
                <dl className="grid gap-8 sm:grid-cols-3">
                    {provider.windows.map((window) => (
                        <div key={window.name}>
                            <dt className="font-mono text-[12px] font-medium text-brand">{window.name}</dt>
                            <dd className="mt-2 text-sm leading-relaxed text-ink-3">{window.body}</dd>
                        </div>
                    ))}
                </dl>
                <p>
                    Hover over the notch to see your remaining usage and reset times. Click a gauge to open usage
                    history with token counts, estimated API cost and a breakdown by model.
                </p>
            </Section>

            <Section title="Sign in">
                <p>{provider.signIn}</p>
            </Section>

            <Section title="Questions">
                <Faq items={provider.faq} />
            </Section>
        </article>
    );
}
