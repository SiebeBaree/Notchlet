import Image from "next/image";

// Exported with Notchlet ShareRenderer using sample usage data.
import shareUsage from "../share-usage.png";

export function SharePreview() {
    return (
        <div
            aria-hidden
            className="flex min-h-[280px] flex-1 items-center justify-center overflow-hidden bg-[radial-gradient(ellipse_at_50%_65%,#cbd6eb,transparent_75%)] px-5 py-10 sm:min-h-[390px] sm:px-6"
        >
            <Image
                src={shareUsage}
                alt=""
                sizes="(min-width: 1280px) 460px, (min-width: 768px) 40vw, 90vw"
                className="h-auto w-full -rotate-3 rounded-md shadow-[0_24px_40px_-12px_rgba(20,35,65,0.35)]"
            />
        </div>
    );
}
