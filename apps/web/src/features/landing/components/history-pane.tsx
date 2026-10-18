import { Settings, Share2 } from "lucide-react";

import { ActivityGrid } from "./activity-grid";

const ranges = [
    { label: "Today", cost: "$12.40", tokens: "9.8M" },
    { label: "7 days", cost: "$96.20", tokens: "78M" },
    { label: "30 days", cost: "$412.10", tokens: "340M" },
];
const models = [
    { name: "Claude Opus", input: "210M", output: "1.9M" },
    { name: "Claude Sonnet", input: "24M", output: "310K" },
];
const months = ["Sep", "Oct", "Nov", "Dec", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug"];

export function HistoryPane() {
    return (
        <div className="w-full max-w-[468px] rounded-[24px] bg-[#060606] p-5 text-white shadow-[0_24px_48px_-15px_rgba(37,32,50,0.32)] sm:p-6">
            <div className="flex items-center gap-3 text-xs font-semibold">
                Usage history
                <Share2 className="ml-auto size-3.5 text-white/55" />
                <Settings className="size-3.5 text-white/55" />
            </div>
            <div className="mt-4 flex items-center gap-4 text-[10px] text-white/60">
                <span className="rounded-full bg-white/12 px-2.5 py-1 text-white">All</span>
                <span>Claude</span>
                <span>Codex</span>
            </div>
            <div className="mt-3 grid grid-cols-3 gap-3 pb-4">
                {ranges.map((range) => (
                    <div key={range.label}>
                        <span className="block text-[10px] text-white/60">{range.label}</span>
                        <span className="my-1 block text-[22px] leading-tight font-semibold tracking-tight sm:text-[26px]">
                            {range.cost}
                        </span>
                        <span className="block text-[10px] text-white/60">{range.tokens} tokens</span>
                    </div>
                ))}
            </div>
            <div className="flex items-center gap-4 border-t border-white/15 pt-3 pb-2 text-[10px]">
                <span>Activity</span>
                <span className="text-white/55">Spend</span>
                <span className="ml-auto text-[8px] text-white/55">Tokens, 12 months</span>
            </div>
            <div className="mb-1 grid grid-cols-12 text-[7px] text-white/50">
                {months.map((month) => (
                    <span key={month}>{month}</span>
                ))}
            </div>
            <ActivityGrid />
            <table className="mt-4 w-full border-t border-white/15 text-[10px]">
                <thead className="text-[9px] text-white/50">
                    <tr>
                        <th className="pt-3 text-left font-normal">Model</th>
                        <th className="pt-3 text-right font-normal">Input</th>
                        <th className="pt-3 text-right font-normal">Output</th>
                    </tr>
                </thead>
                <tbody>
                    {models.map((model) => (
                        <tr key={model.name}>
                            <td className="pt-2">{model.name}</td>
                            <td className="pt-2 text-right">{model.input}</td>
                            <td className="pt-2 text-right">{model.output}</td>
                        </tr>
                    ))}
                </tbody>
            </table>
            <p className="mt-4 text-[8px] text-white/55">Cost at API list prices · History since Aug 31</p>
        </div>
    );
}
