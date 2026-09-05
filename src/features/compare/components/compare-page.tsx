import { Section } from "@/components/article";

import { type Competitor, notchlet, rows } from "../competitors";

// One comparison: the same eight facts side by side, then who should pick which. The other tool gets the honest
// version, since a reader who catches one stretched claim stops believing the rest.
export function ComparePage({ competitor }: { competitor: Competitor }) {
    return (
        <article className="bg-white">
            <header className="relative overflow-hidden px-6 pt-40 pb-20">
                <div
                    aria-hidden
                    className="absolute inset-0 bg-[radial-gradient(60%_60%_at_50%_0%,#efeafd,transparent_70%)]"
                />
                <div className="relative mx-auto max-w-3xl">
                    <p className="font-mono text-[12px] font-medium text-brand">Compared</p>
                    <h1 className="mt-5 font-display text-[42px] leading-[1.08] tracking-[-0.005em] text-balance text-ink sm:text-[60px]">
                        Notchlet vs {competitor.name}
                    </h1>
                    <p className="mt-6 max-w-xl text-[15px] leading-relaxed text-ink-3">{competitor.summary}</p>
                </div>
            </header>

            <Section title="Side by side." sub={`Checked ${competitor.source.checked}.`}>
                <table className="w-full border-collapse text-left text-sm">
                    <thead>
                        <tr className="text-[15px] font-semibold tracking-tight text-ink">
                            <th className="w-[22%] pb-4 font-mono text-[12px] font-medium text-brand" scope="col">
                                &nbsp;
                            </th>
                            <th className="w-[39%] pr-6 pb-4" scope="col">
                                Notchlet
                            </th>
                            <th className="w-[39%] pb-4" scope="col">
                                {competitor.name}
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        {rows.map((row) => (
                            <tr key={row.key} className="border-t border-line align-top">
                                <th className="py-4 pr-4 font-mono text-[12px] font-medium text-brand" scope="row">
                                    {row.label}
                                </th>
                                <td className="py-4 pr-6 leading-relaxed text-ink-2">{notchlet[row.key]}</td>
                                <td className="py-4 leading-relaxed text-ink-3">{competitor.facts[row.key]}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
                <p className="text-[13px] text-ink-3">
                    {competitor.name} facts from{" "}
                    <a
                        href={competitor.source.href}
                        target="_blank"
                        rel="noreferrer"
                        className="font-medium text-brand underline underline-offset-4 transition-colors hover:text-ink"
                    >
                        {competitor.source.label}
                    </a>
                    . If one is wrong, open an issue and it gets fixed.
                </p>
            </Section>

            <Section title="Which one." sub="Pick by what you run.">
                <div className="grid gap-10 sm:grid-cols-2">
                    <Picks title={`${competitor.name} if`} items={competitor.pickThem} />
                    <Picks title="Notchlet if" items={competitor.pickUs} />
                </div>
            </Section>
        </article>
    );
}

function Picks({ title, items }: { title: string; items: string[] }) {
    return (
        <div>
            <h3 className="text-[15px] font-semibold tracking-tight text-ink">{title}</h3>
            <ul className="mt-4 flex flex-col gap-3">
                {items.map((item) => (
                    <li key={item} className="flex gap-3 text-sm leading-relaxed text-ink-3">
                        <span aria-hidden className="mt-2.5 size-1 shrink-0 rounded-full bg-brand" />
                        {item}
                    </li>
                ))}
            </ul>
        </div>
    );
}
