"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

import { Button } from "@/components/ui/button";

export default function TodosError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
    useEffect(() => {
        Sentry.captureException(error);
    }, [error]);

    return (
        <main className="mx-auto flex max-w-md flex-col items-start gap-4 px-6 py-16">
            <h1 className="text-xl font-semibold">Something went wrong</h1>
            <p className="text-sm text-muted-foreground">
                The error has been reported.{error.digest ? ` Reference: ${error.digest}` : ""}
            </p>
            <Button onClick={reset}>Try again</Button>
        </main>
    );
}
