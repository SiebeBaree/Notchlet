import type { FaqItem } from "@/components/json-ld";

// Where the agent itself shows the numbers: a slash command in the CLI or a page on the web.
type BuiltIn = { body: string } & ({ command: string; where: string } | { link: { href: string; label: string } });

export type Provider = {
    slug: string;
    name: string;
    title: string;
    description: string;
    heading: string;
    intro: string;
    builtIn: BuiltIn;
    windows: { name: string; body: string }[];
    signIn: string;
    faq: FaqItem[];
};

// One page per agent, at /<slug>. The facts mirror the provider files in the app repo; when a provider changes there,
// change it here.
export const providers: Provider[] = [
    {
        slug: "claude-code",
        name: "Claude Code",
        title: "Check your Claude Code usage from the notch",
        description:
            "How to see how much of your Claude Code 5 hour and weekly limit is left, in the CLI with /usage or in your Mac's notch with Notchlet.",
        heading: "Check your Claude Code usage.",
        intro: "See your Claude Code session and weekly limits from the notch. Notchlet shows remaining usage, reset times and any separate limits your plan has for individual models.",
        builtIn: {
            command: "/usage",
            where: "inside a Claude Code session",
            body: "The command shows session usage, weekly usage and their reset times.",
        },
        windows: [
            {
                name: "5h session",
                body: "A rolling window that starts with your first message and resets five hours later.",
            },
            { name: "Weekly", body: "Every model together, reset once a week." },
            { name: "Per model", body: "A second weekly cap for some models, shown as its own ring." },
        ],
        signIn: "Notchlet can use your Claude Code or Claude Desktop login. Choose a login source in provider settings. It reads saved credentials on your Mac and refreshes an expired Claude Code token using the same locking process as the CLI.",
        faq: [
            {
                q: "How do I check my Claude Code usage?",
                a: "Run /usage in a Claude Code session, or install Notchlet and hover the notch. Both read the same numbers.",
            },
            {
                q: "Does Notchlet spend Claude Code usage to check it?",
                a: "No. The usage endpoint reports the windows. It does not start a conversation.",
            },
            {
                q: "Do I need to paste an API key?",
                a: "No. Notchlet uses the login Claude Code already has. A Console API key would not show plan usage anyway.",
            },
        ],
    },
    {
        slug: "codex",
        name: "Codex",
        title: "Check your Codex usage from the notch",
        description:
            "How to see how much of your Codex rate limit is left, in the CLI with /status or in your Mac's notch with Notchlet.",
        heading: "Check your Codex usage.",
        intro: "See the Codex usage limits for your ChatGPT plan from the notch. Notchlet reads the windows and reset times reported by Codex.",
        builtIn: {
            command: "/status",
            where: "in the Codex CLI",
            body: "The command lists each usage window and its reset time.",
        },
        windows: [
            { name: "5h", body: "A rolling window, on the plans that have one." },
            { name: "Weekly", body: "Reset once a week." },
            {
                name: "Per plan",
                body: "The available windows depend on your plan. Notchlet uses the labels and durations reported by Codex.",
            },
        ],
        signIn: "Notchlet uses the login saved by the Codex CLI. If the login expires, open Codex to renew it. Notchlet does not refresh Codex tokens itself.",
        faq: [
            {
                q: "How do I check my Codex usage?",
                a: "Run /status in the Codex CLI, or hover the notch with Notchlet installed.",
            },
            {
                q: "Does it work with a ChatGPT Plus plan?",
                a: "Yes. Any plan the Codex CLI signs into. The windows come from the endpoint per plan.",
            },
            { q: "Does Notchlet need my OpenAI API key?", a: "No. It uses the Codex CLI's login." },
        ],
    },
    {
        slug: "cursor",
        name: "Cursor",
        title: "Check your Cursor usage from the notch",
        description:
            "How to see how much of your Cursor monthly budget is left without opening the dashboard, in your Mac's notch with Notchlet.",
        heading: "Check your Cursor usage.",
        intro: "See your remaining Cursor budget from the notch, including the separate pools for Cursor models and other models. Reset times follow your billing cycle.",
        builtIn: {
            link: { href: "https://cursor.com/dashboard", label: "Open the Cursor dashboard" },
            body: "The Usage tab shows your monthly usage and the separate model pools.",
        },
        windows: [
            { name: "Monthly", body: "The blended headline the dashboard shows, reset with the billing cycle." },
            { name: "Cursor models", body: "The pool for Cursor's own models, such as Composer." },
            { name: "Other models", body: "The pool for third-party models." },
        ],
        signIn: "Notchlet uses your Cursor app login. If Cursor is not installed on this Mac, add a session token in Notchlet settings. Pasted tokens are stored in the macOS keychain.",
        faq: [
            {
                q: "How do I check my Cursor usage?",
                a: "The Usage tab on cursor.com/dashboard, or hover the notch with Notchlet installed.",
            },
            {
                q: "Does Notchlet show on-demand spend?",
                a: "No. The gauges show your included budget. Check the Cursor dashboard for on-demand charges.",
            },
            {
                q: "Where does Cursor history come from?",
                a: "From the dashboard's usage export, so it covers your whole account, not only this Mac.",
            },
        ],
    },
    {
        slug: "opencode",
        name: "OpenCode",
        title: "Check your OpenCode usage from the notch",
        description:
            "How to see how much of your OpenCode Go 5 hour, weekly and monthly windows is left, in your Mac's notch with Notchlet.",
        heading: "Check your OpenCode Go usage.",
        intro: "Track OpenCode Go usage from the notch. Notchlet shows the five-hour, weekly and monthly windows for your subscription. It does not track Zen credits.",
        builtIn: {
            link: { href: "https://opencode.ai", label: "Open opencode.ai" },
            body: "The dashboard shows Go usage windows and Zen credits.",
        },
        windows: [
            { name: "5h", body: "A rolling window." },
            { name: "Weekly", body: "Monday to Monday, UTC." },
            { name: "Monthly", body: "Anchored to your subscription date." },
        ],
        signIn: "Notchlet uses the key OpenCode saved after /connect. You can also add a key in Notchlet settings, where it is stored in the macOS keychain. Reconnect if you rotate the key.",
        faq: [
            {
                q: "Does Notchlet show Zen credits?",
                a: "No. Notchlet tracks OpenCode Go subscriptions. Check the OpenCode dashboard for Zen credits.",
            },
            {
                q: "How do I check my OpenCode usage?",
                a: "On the opencode.ai dashboard, or hover the notch with Notchlet installed.",
            },
            { q: "Where does OpenCode history come from?", a: "From OpenCode's message database on this Mac." },
        ],
    },
];

export function providerFor(slug: string) {
    return providers.find((provider) => provider.slug === slug);
}
