import { ArrowUpRight } from "lucide-react";
import type { ReactNode } from "react";

import { cn } from "@/lib/utils";

import { githubUrl } from "../links";
import { AgentNotificationsPreview } from "./agent-notifications-preview";
import { HistoryPane } from "./history-pane";
import { LoginPreview, PacePreview } from "./product-details";
import { SecretScanPreview } from "./secret-scan-preview";
import { SharePreview } from "./share-preview";

function ProductDemo({
    title,
    description,
    children,
    compact = false,
}: {
    title: string;
    description: string;
    children: ReactNode;
    compact?: boolean;
}) {
    return (
        <figure
            className={cn(
                "flex min-w-0 flex-col overflow-hidden rounded-lg border border-[#efedf4] bg-[#f7f6fa]",
                !compact && "md:row-span-2 md:grid md:grid-rows-subgrid md:gap-0",
                compact &&
                    "grid grid-cols-1 grid-rows-[11rem_1fr] sm:grid-cols-[1fr_1.1fr] sm:grid-rows-1 md:grid-cols-1 md:grid-rows-[11rem_1fr]",
            )}
        >
            {children}
            <figcaption className={cn("px-6 py-6 lg:px-7", compact && "px-5 pt-2 pb-6 sm:py-5 md:pt-2")}>
                <h3 className={cn("text-base font-semibold tracking-tight text-ink", compact && "text-sm")}>{title}</h3>
                <p className="mt-2 max-w-sm text-xs leading-relaxed text-ink-3">{description}</p>
            </figcaption>
        </figure>
    );
}

export function History() {
    return (
        <section
            id="features"
            aria-labelledby="features-heading"
            className="border-b border-line px-5 py-14 sm:px-8 sm:py-16 lg:py-20"
        >
            <div className="mb-8 flex flex-wrap items-end justify-between gap-6">
                <div>
                    <h2
                        id="features-heading"
                        className="text-[26px] leading-tight font-semibold tracking-tight text-ink sm:text-[30px]"
                    >
                        Usage history and agent tools.
                    </h2>
                    <p className="mt-3 max-w-xl text-[15px] leading-relaxed text-ink-3">
                        Track your usage, catch pasted secrets and know when an agent needs you.
                    </p>
                </div>
                <a
                    href={githubUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1.5 text-xs font-medium text-brand transition-colors hover:text-ink"
                >
                    View source on GitHub <ArrowUpRight className="size-3.5" />
                </a>
            </div>
            <div className="grid gap-4 md:grid-cols-[1.3fr_1fr]">
                <ProductDemo
                    title="Browse your usage history"
                    description="Daily activity, token counts and cost estimates, broken down by provider and model."
                >
                    <div
                        aria-hidden
                        className="flex min-h-[340px] flex-1 items-center justify-center bg-[radial-gradient(ellipse_at_50%_75%,#d7cceb77,transparent_65%)] px-5 pt-8 pb-2 sm:min-h-[390px] sm:px-8"
                    >
                        <HistoryPane />
                    </div>
                </ProductDemo>
                <ProductDemo
                    title="Share your usage"
                    description="Save your graph as a PNG or copy it straight into a post."
                >
                    <SharePreview />
                </ProductDemo>
            </div>
            <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
                <ProductDemo
                    compact
                    title="See your usage pace"
                    description="Check whether your usage is on track to last until the next reset."
                >
                    <div aria-hidden className="flex h-44 items-center justify-center px-5">
                        <PacePreview />
                    </div>
                </ProductDemo>
                <ProductDemo
                    compact
                    title="Secret scanning"
                    description="Find secrets pasted into Claude Code and Codex chats. Scans run locally on Apple silicon Macs."
                >
                    <div aria-hidden className="flex h-44 items-center justify-center px-5">
                        <SecretScanPreview />
                    </div>
                </ProductDemo>
                <ProductDemo
                    compact
                    title="Agent notifications"
                    description="A blue outline means an agent finished its turn. Amber means it needs permission or an answer."
                >
                    <div aria-hidden className="flex h-44 items-center justify-center px-5">
                        <AgentNotificationsPreview />
                    </div>
                </ProductDemo>
                <ProductDemo
                    compact
                    title="Use your existing logins"
                    description="Connect the tools already on your Mac. No Notchlet account needed."
                >
                    <div aria-hidden className="flex h-44 items-center justify-center px-4">
                        <LoginPreview />
                    </div>
                </ProductDemo>
            </div>
            <p className="mt-5 text-[11px] leading-relaxed text-ink-3">
                Illustrations show sample data. Cost estimates use API list prices and are not your subscription bill.
            </p>
        </section>
    );
}
