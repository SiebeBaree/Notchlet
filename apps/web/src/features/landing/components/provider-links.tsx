import Image from "next/image";
import Link from "next/link";

import { supportedProviders } from "../supported-providers";

export function ProviderLinks() {
    return (
        <nav
            aria-label="Supported providers"
            className="flex flex-wrap items-center justify-center gap-x-9 gap-y-5 border-y border-line px-6 py-7 sm:gap-x-14"
        >
            {supportedProviders.map((provider) => (
                <Link
                    key={provider.name}
                    href={provider.href}
                    className="flex items-center gap-2.5 text-xs font-medium text-ink-2 transition-colors hover:text-brand sm:text-sm"
                >
                    <Image src={provider.icon} alt="" width={20} height={20} className="size-5 object-contain invert" />
                    {provider.name}
                </Link>
            ))}
        </nav>
    );
}
