import { connection } from "next/server";

import { JsonLd } from "@/components/json-ld";
import {
    Cta,
    DeviceScroll,
    Footer,
    History,
    MenuBar,
    Pricing,
    ProviderLinks,
    Questions,
    Roadmap,
    softwareApplication,
} from "@/features/landing";

export default async function HomePage() {
    // Nonce-based CSP requires dynamic rendering (see proxy.ts).
    await connection();

    return (
        <main className="bg-white">
            <JsonLd data={softwareApplication} />
            <MenuBar />
            <DeviceScroll />
            <div className="mx-auto max-w-7xl border-x border-line sm:mx-6 xl:mx-auto">
                <ProviderLinks />
                <History />
                <Roadmap />
                <Pricing />
                <Questions />
                <Cta />
                <Footer />
            </div>
        </main>
    );
}
