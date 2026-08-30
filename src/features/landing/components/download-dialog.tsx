"use client";

import type { ReactNode } from "react";

import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
    DialogTrigger,
} from "@/components/ui/dialog";

import { SignupForm } from "./signup-form";

// Every download button on the page opens this until launch day, so it collects the address instead of dead-ending.
export function DownloadDialog({ children }: { children: ReactNode }) {
    return (
        <Dialog>
            <DialogTrigger asChild>{children}</DialogTrigger>
            <DialogContent
                showCloseButton={false}
                className="w-[min(calc(100%-4rem),380px)] rounded-3xl bg-black/75 p-8 text-center text-white ring-white/10 backdrop-blur-2xl"
            >
                <DialogHeader className="gap-2.5">
                    <DialogTitle className="text-lg text-white">Monday, 13:00 CEST</DialogTitle>
                    <DialogDescription className="text-white/60">
                        Drop your email and I will send you the link. One email, then never again.
                    </DialogDescription>
                </DialogHeader>
                <div className="mt-2">
                    <SignupForm />
                </div>
            </DialogContent>
        </Dialog>
    );
}
