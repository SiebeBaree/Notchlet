import { ArrowUpRight } from "lucide-react";

import { Code, Faq, Section } from "@/components/article";

import type { Provider } from "../providers";

// The page for one agent: what its limits are, where it shows them itself, and what Notchlet does instead.
export function ProviderPage({ provider }: { provider: Provider }) {
    const { builtIn } = provider;
    return (
        <article className="bg-white">
            <header className="relative overflow-hidden px-6 pt-40 pb-20">
                <div
                    aria-hidden
                    className="absolute inset-0 bg-[radial-gradient(60%_60%_at_50%_0%,#efeafd,transparent_70%)]"
                />
                <div className="relative mx-auto max-w-3xl">
                    <p className="font-mono text-[12px] font-medium text-brand">{provider.name}</p>
                    <h1 className="mt-5 font-display text-[42px] leading-[1.08] tracking-[-0.005em] text-balance text-ink sm:text-[60px]">
                        {provider.heading}
                    </h1>
                    <p className="mt-6 max-w-xl text-[15px] leading-relaxed text-ink-3">{provider.intro}</p>
                </div>
            </header>

            <Section title="The built-in way." sub={builtIn.sub}>
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

            <Section title="What Notchlet shows." sub="One ring per window.">
                <dl className="grid gap-8 sm:grid-cols-3">
                    {provider.windows.map((window) => (
                        <div key={window.name}>
                            <dt className="font-mono text-[12px] font-medium text-brand">{window.name}</dt>
                            <dd className="mt-2 text-sm leading-relaxed text-ink-3">{window.body}</dd>
                        </div>
                    ))}
                </dl>
                <p>
                    Hover the notch and each window is a ring with the percentage left, the reset time and a verdict on
                    your burn rate. Click a ring for history: cost and tokens per day, and every model you used.
                </p>
            </Section>

            <Section title="How it signs in." sub="With the login you already have.">
                <p>{provider.signIn}</p>
            </Section>

            <Section title="Questions." sub="Short answers.">
                <Faq items={provider.faq} />
            </Section>
        </article>
    );
}
