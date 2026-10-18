import { Faq } from "@/components/article";
import type { FaqItem } from "@/components/json-ld";

const questions: FaqItem[] = [
    {
        q: "Does it work on a Mac without a notch?",
        a: "Yes. Notchlet adds a virtual notch at the top of the screen, including on external displays. macOS 14 or later is required.",
    },
    {
        q: "Do I need an account or API key?",
        a: "You do not need a Notchlet account. It uses the provider logins already on your Mac. Cursor and OpenCode also support a token or key added in settings.",
    },
    {
        q: "Does checking usage use my allowance?",
        a: "No. Notchlet reads your provider's usage data. It does not send a prompt to a model.",
    },
    {
        q: "Which tools does it support?",
        a: "Claude Code, Codex, Cursor and OpenCode Go, with up to three providers visible at once. OpenCode Zen credits are not supported.",
    },
    {
        q: "What does Notchlet send from my Mac?",
        a: "Notchlet contacts your providers to retrieve usage data and checks for app updates. Release builds also send anonymous product analytics, which you can turn off in settings. Usage numbers, chat contents, credentials and secret findings are not included in analytics. Builds from source send no analytics.",
    },
    {
        q: "Where does my usage history come from?",
        a: "It comes from your tools' logs and usage records: Claude Code transcripts, Codex sessions, OpenCode's local database and Cursor's usage export. Cost is estimated at API list prices and is not your subscription bill.",
    },
];

export function Questions() {
    return (
        <section
            aria-labelledby="questions-heading"
            className="grid gap-8 border-b border-line px-5 py-14 sm:px-8 sm:py-16 md:grid-cols-[1fr_1.4fr] md:gap-14 lg:py-20"
        >
            <h2 id="questions-heading" className="text-[26px] font-semibold tracking-tight text-ink sm:text-[30px]">
                Questions
            </h2>
            <Faq items={questions} />
        </section>
    );
}
