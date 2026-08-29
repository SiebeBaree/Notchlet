import { ArrowRight } from "lucide-react";
import Link from "next/link";
import { connection } from "next/server";

import { Button } from "@/components/ui/button";

export default async function HomePage() {
    // Nonce-based CSP requires dynamic rendering (see proxy.ts).
    await connection();

    return (
        <main className="mx-auto flex min-h-dvh max-w-md flex-col items-start justify-center gap-4 px-6">
            <h1 className="text-3xl font-semibold tracking-tight">Todos</h1>
            <p className="text-muted-foreground">
                A deliberately small app demonstrating how this codebase is organized: routes compose, features
                implement, lib carries the infrastructure.
            </p>
            <Button asChild>
                <Link href="/todos">
                    Open todos
                    <ArrowRight data-icon="inline-end" />
                </Link>
            </Button>
        </main>
    );
}
