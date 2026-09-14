import { KeyRound } from "lucide-react";

export function SecretScanPreview() {
    return (
        <div className="w-full max-w-[280px] rounded-2xl bg-black p-4 text-white shadow-[0_14px_28px_rgba(25,18,38,0.13)]">
            <div className="flex items-center gap-2 text-[10px] text-white/65">
                <KeyRound className="size-3 shrink-0 text-[#e5ac40]" />1 leaked secret in Claude chats
            </div>
            <p className="mt-3 text-xs font-semibold">OpenAI API Key</p>
            <p className="mt-2 rounded-md bg-white/6 px-2.5 py-2 font-mono text-[11px] text-[#e5ac40]">sk-proj…Wk</p>
            <div className="mt-3 flex items-center gap-3 text-[9px]">
                <span className="rounded bg-white/10 px-2 py-1">How to solve this</span>
                <span className="text-white/50">Ignore</span>
            </div>
        </div>
    );
}
