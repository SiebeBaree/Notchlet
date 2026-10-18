import { ArticleHeader, Section } from "@/components/article";

import { type Competitor, notchlet, rows } from "../competitors";

export function ComparePage({ competitor }: { competitor: Competitor }) {
    return (
        <article className="mx-auto max-w-7xl border-x border-line bg-white sm:mx-6 xl:mx-auto">
            <ArticleHeader title={`Notchlet vs ${competitor.name}`}>
                <p>{competitor.summary}</p>
            </ArticleHeader>

            <Section title="Feature comparison" sub={`Checked ${competitor.source.checked}.`}>
                <table className="w-full table-fixed border-collapse text-left text-xs [overflow-wrap:anywhere] sm:text-sm">
                    <thead>
                        <tr className="text-[15px] font-semibold tracking-tight text-ink">
                            <th className="w-[22%] pb-4 font-mono text-[12px] font-medium text-brand" scope="col">
                                &nbsp;
                            </th>
                            <th className="w-[39%] pr-3 pb-4 sm:pr-6" scope="col">
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
                                <th
                                    className="py-4 pr-2 font-mono text-[12px] font-medium text-brand sm:pr-4"
                                    scope="row"
                                >
                                    {row.label}
                                </th>
                                <td className="py-4 pr-3 leading-relaxed text-ink-2 sm:pr-6">{notchlet[row.key]}</td>
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
                    .
                </p>
            </Section>

            <Section title="Choosing a tool">
                <div className="grid gap-10 sm:grid-cols-2">
                    <Picks title={`Choose ${competitor.name} if`} items={competitor.pickThem} />
                    <Picks title="Choose Notchlet if" items={competitor.pickUs} />
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
