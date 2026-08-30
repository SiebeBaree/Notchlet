"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useMutation } from "@tanstack/react-query";
import { useForm } from "react-hook-form";

import { Input } from "@/components/ui/input";
import { ActionError, unwrap } from "@/lib/action/result";
import { toastActionError } from "@/lib/action/toast";
import { track } from "@/lib/analytics";

import { signUpForLaunch } from "../actions";
import { signupSchema, type SignupInput } from "../schema";

// Used on the dark dialog and over the hero wallpaper, so the light shadcn Input needs its colors inverted and
// enough of its own backdrop to stay legible on a bright wallpaper.
const inputClass =
    "h-10 rounded-lg border-white/20 bg-black/25 text-white backdrop-blur-md placeholder:text-white/50 focus-visible:border-white/40 focus-visible:ring-white/20 aria-invalid:border-red-400/60 aria-invalid:ring-red-400/20";

export function SignupForm() {
    const form = useForm<SignupInput>({
        resolver: zodResolver(signupSchema),
        defaultValues: { email: "" },
    });

    const signUp = useMutation({
        mutationFn: async (input: SignupInput) => unwrap(await signUpForLaunch(input)),
        onSuccess: () => track("launch_signup"),
        onError: (error) => {
            const emailError = error instanceof ActionError ? error.fieldErrors?.email?.[0] : undefined;
            if (emailError) {
                form.setError("email", { message: emailError });
                return;
            }
            toastActionError(error);
        },
    });

    if (signUp.isSuccess) {
        return <p className="text-sm text-white/80">You are on the list. The link lands Monday.</p>;
    }

    const emailError = form.formState.errors.email?.message;

    return (
        <form onSubmit={form.handleSubmit((input) => signUp.mutate(input))} noValidate>
            <div className="flex gap-2">
                <Input
                    {...form.register("email")}
                    type="email"
                    placeholder="you@example.com"
                    aria-label="Email address"
                    aria-invalid={emailError ? true : undefined}
                    autoComplete="email"
                    className={inputClass}
                />
                <button
                    type="submit"
                    disabled={signUp.isPending}
                    className="h-10 shrink-0 cursor-pointer rounded-lg bg-white px-4 text-sm font-medium text-black transition-opacity hover:opacity-90 disabled:opacity-60"
                >
                    Notify me
                </button>
            </div>
            {emailError ? (
                <p role="alert" className="mt-2 text-left text-sm text-red-300">
                    {emailError}
                </p>
            ) : null}
        </form>
    );
}
