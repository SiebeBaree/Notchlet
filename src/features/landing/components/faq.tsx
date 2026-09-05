import { Faq } from "@/components/article";
import type { FaqItem } from "@/components/json-ld";

const questions: FaqItem[] = [
    {
        q: "Does Notchlet spend usage to measure usage?",
        a: "No. It calls the usage endpoint your CLI calls behind /usage or /status. That endpoint reports the windows without starting a conversation.",
    },
    {
        q: "Do I need an API key or an account?",
        a: "No. Notchlet reads the login the CLIs already wrote to your Mac: Claude Code's keychain item, Codex's auth.json, Cursor's state database and the key OpenCode saved after /connect. Cursor and OpenCode also take a pasted token for a Mac without the app.",
    },
    {
        q: "Does it work on a Mac without a notch?",
        a: "Yes. On a Mac or external display without one it draws a virtual notch at the top center of the screen. macOS 14 or later.",
    },
    {
        q: "What leaves my Mac?",
        a: 'Your usage numbers, credentials and chats stay on the machine. Notchlet sends anonymous product analytics, a random ID plus events like "the notch was opened". The full list is one file in the repo and one toggle in settings turns it off. Builds from source send nothing.',
    },
    {
        q: "Which agents does it track?",
        a: "Claude Code, Codex, Cursor and OpenCode, three at a time. Installed CLIs switch on by themselves. Adding an agent is one file in the repo.",
    },
    {
        q: "Where does the history come from?",
        a: "From what each agent already keeps: Claude Code's transcripts, Codex's session rollouts, OpenCode's message database and Cursor's usage export. Cost is what the same tokens would cost at API list prices. A subscription does not bill per token, so read it as a value, not a bill.",
    },
    {
        q: "What does it cost?",
        a: "Nothing. Notchlet is free and MIT licensed. There is no paid tier and none planned.",
    },
];

export function Questions() {
    return (
        <section className="border-t border-line bg-white px-6 py-28">
            <div className="mx-auto max-w-6xl">
                <h2 className="max-w-2xl text-[26px] leading-[1.25] font-semibold tracking-tight text-ink sm:text-[30px]">
                    Questions. <span className="text-ink-3">Short answers.</span>
                </h2>
                <div className="mt-14">
                    <Faq items={questions} />
                </div>
            </div>
        </section>
    );
}
