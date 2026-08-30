import { Countdown } from "./countdown";
import { DownloadDialog } from "./download-dialog";

export function Cta() {
    return (
        <section className="border-t border-line bg-linear-to-b from-[#f6f4fb] to-[#e9e5f5] px-6 py-32">
            <div className="mx-auto flex max-w-2xl flex-col items-center text-center">
                <h2 className="font-display text-[42px] leading-[1.08] tracking-[-0.005em] text-balance text-ink sm:text-[56px]">
                    Stop finding out you are rate limited the hard way.
                </h2>
                <div className="mt-12">
                    <Countdown surface="light" />
                </div>
                <DownloadDialog>
                    <button
                        type="button"
                        className="mt-12 cursor-pointer rounded-md bg-ink px-6 py-3 text-[15px] font-medium text-white transition-colors hover:bg-ink-2"
                    >
                        Get Notchlet
                    </button>
                </DownloadDialog>
            </div>
        </section>
    );
}
