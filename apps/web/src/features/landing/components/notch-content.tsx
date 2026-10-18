import { Settings } from "lucide-react";
import Image from "next/image";

const gauges = [
    { label: "5h", pct: 100, color: "#ffffff" },
    { label: "Weekly", pct: 90, color: "#30d158", resets: "Resets Sat 11:00 AM", status: "Plenty" },
    { label: "Fable", pct: 82, color: "#ffd60a", resets: "Resets Sat 11:00 AM", status: "On pace" },
] as const;

function Gauge({ gauge }: { gauge: (typeof gauges)[number] }) {
    const radius = 32;
    const circumference = 2 * Math.PI * radius;
    return (
        <div className="flex flex-col items-center">
            <span className="text-[13px] font-semibold text-white">{gauge.label}</span>
            <div className="relative mt-1.5 size-[72px]">
                <svg viewBox="0 0 72 72" className="size-full -rotate-90">
                    <circle cx="36" cy="36" r={radius} fill="none" stroke="#3a3a3c" strokeWidth="5.5" />
                    <circle
                        cx="36"
                        cy="36"
                        r={radius}
                        fill="none"
                        stroke={gauge.color}
                        strokeWidth="5.5"
                        strokeLinecap="round"
                        strokeDasharray={`${(circumference * gauge.pct) / 100} ${circumference}`}
                    />
                </svg>
                <div className="absolute inset-0 flex flex-col items-center justify-center">
                    <span className="text-[13px] leading-none font-bold text-white">{gauge.pct}%</span>
                    <span className="mt-0.5 text-[9px] leading-none text-white/60">left</span>
                </div>
            </div>
            {"resets" in gauge && (
                <>
                    <span className="mt-2 text-[10px] leading-none text-white/50">{gauge.resets}</span>
                    <span className="mt-1 text-[11px] leading-none font-medium" style={{ color: gauge.color }}>
                        {gauge.status}
                    </span>
                </>
            )}
        </div>
    );
}

export function NotchContent({ hideHeaderOnMobile = false }: { hideHeaderOnMobile?: boolean }) {
    return (
        <>
            <div className={`items-center justify-between ${hideHeaderOnMobile ? "hidden sm:flex" : "flex"}`}>
                <span className="flex items-center gap-1.5 text-[13px] font-semibold text-white">
                    <Image src="/claude-ai-icon.svg" alt="" width={14} height={14} />
                    Claude
                </span>
                <Settings aria-hidden className="size-3.5 text-white/40" />
            </div>
            <div className="mt-1.5 grid grid-cols-3 gap-2">
                {gauges.map((gauge) => (
                    <Gauge key={gauge.label} gauge={gauge} />
                ))}
            </div>
        </>
    );
}
