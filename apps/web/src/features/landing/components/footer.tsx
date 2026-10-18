import { githubIssuesUrl, githubUrl, xUrl } from "../links";

const links = [
    { label: "GitHub", href: githubUrl },
    { label: "Roadmap", href: githubIssuesUrl },
    { label: "X", href: xUrl },
];

export function Footer() {
    return (
        <footer className="border-t border-line bg-white px-6 py-10">
            <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4">
                <span className="flex items-center gap-2 text-sm font-semibold text-ink">
                    <span aria-hidden className="h-[13px] w-5 rounded-[4px_4px_7px_7px] bg-ink/90" />
                    Notchlet
                </span>
                <div className="flex items-center gap-6 text-[13px] text-ink-3">
                    {links.map((link) => (
                        <a
                            key={link.label}
                            href={link.href}
                            target="_blank"
                            rel="noreferrer"
                            className="transition-colors hover:text-ink"
                        >
                            {link.label}
                        </a>
                    ))}
                    <span>MIT licensed</span>
                </div>
            </div>
        </footer>
    );
}
