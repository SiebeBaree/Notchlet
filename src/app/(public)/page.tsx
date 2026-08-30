import { connection } from "next/server";

import { Cta, DeviceScroll, Footer, MenuBar, Pricing, Roadmap } from "@/features/landing";

export default async function HomePage() {
    // Nonce-based CSP requires dynamic rendering (see proxy.ts).
    await connection();

    return (
        <main className="bg-white">
            <MenuBar />
            <DeviceScroll />
            <Roadmap />
            <Pricing />
            <Cta />
            <Footer />
        </main>
    );
}
