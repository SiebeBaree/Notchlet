import type { FaqItem } from "@/components/json-ld";

// Where the agent itself shows the numbers: a slash command in the CLI or a page on the web.
type BuiltIn = { sub: string; body: string } & (
    | { command: string; where: string }
    | { link: { href: string; label: string } }
);

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
        heading: "Claude Code usage, without /usage.",
        intro: "Claude Code caps you twice: a rolling 5 hour session and a weekly cap, with a separate weekly cap for some models. Hit either and Claude stops mid task until the window resets. The CLI knows the numbers and keeps them behind a slash command.",
        builtIn: {
            sub: "Ask the CLI.",
            command: "/usage",
            where: "inside a Claude Code session",
            body: "It shows the session bar, the weekly bar and their reset times. That works, once, and it costs a terminal switch every time you want to look.",
        },
        windows: [
            {
                name: "5h session",
                body: "A rolling window that starts with your first message and resets five hours later.",
            },
            { name: "Weekly", body: "Every model together, reset once a week." },
            { name: "Per model", body: "A second weekly cap for some models, shown as its own ring." },
        ],
        signIn: "Notchlet reads the token Claude Code keeps in your keychain, with its credentials file as fallback, and calls the endpoint behind /usage. It reads the item the way Claude Code writes it, so there is no password prompt. When the token expires while Claude Code is idle, Notchlet refreshes it the way a second Claude Code process would, with the same locks and the same write-back, so Claude Code stays signed in.",
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
        heading: "Codex usage, without /status.",
        intro: "Codex meters your ChatGPT plan per window, and which windows you get depends on the plan: a 5 hour and a weekly window on Plus, weekly only on the Pro tiers. The CLI reports them behind /status.",
        builtIn: {
            sub: "Ask the CLI.",
            command: "/status",
            where: "in the Codex CLI",
            body: "It lists each window with the percentage used and the reset time. Then you switch back to whatever you were doing and forget the number.",
        },
        windows: [
            { name: "5h", body: "A rolling window, on the plans that have one." },
            { name: "Weekly", body: "Reset once a week." },
            {
                name: "Per plan",
                body: "Notchlet shows whatever the endpoint returns for your plan, with the labels and durations it sends. There is no plan table to go stale.",
            },
        ],
        signIn: "Notchlet reads the tokens the Codex CLI stores in ~/.codex/auth.json and calls the endpoint behind /status. It never refreshes them: they last ten days, the CLI renews them on use, and OpenAI rejects a reused refresh token, so a refresh behind the CLI's back could sign it out.",
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
        heading: "Cursor usage, without the dashboard.",
        intro: "Cursor's included usage is a monthly budget split in two pools, Cursor's own models and third-party models, both reset with your billing cycle. Past the budget you pay on demand. The only place Cursor shows the numbers is the usage tab of its web dashboard.",
        builtIn: {
            sub: "Open the dashboard.",
            link: { href: "https://cursor.com/dashboard", label: "Open the Cursor dashboard" },
            body: "The Usage tab shows the blended headline and the two pools. It is a browser tab away from your editor, which is one tab too many to check every hour.",
        },
        windows: [
            { name: "Monthly", body: "The blended headline the dashboard shows, reset with the billing cycle." },
            { name: "Cursor models", body: "The pool for Cursor's own models, such as Composer." },
            { name: "Other models", body: "The pool for third-party models." },
        ],
        signIn: "Notchlet reads the access token Cursor.app keeps in its state database and calls the endpoint behind the dashboard's usage page, the way the dashboard itself does. Cursor.app rotates the token and Notchlet picks up the new one on the next poll. If you use Cursor without the app on this Mac, paste a session token in Notchlet's settings. It lives in Notchlet's own keychain item.",
        faq: [
            {
                q: "How do I check my Cursor usage?",
                a: "The Usage tab on cursor.com/dashboard, or hover the notch with Notchlet installed.",
            },
            {
                q: "Does Notchlet show on-demand spend?",
                a: "No. Spend past the budget is a bill, not a limit, so it stays out of the ring.",
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
        heading: "OpenCode Go usage, without the dashboard.",
        intro: "OpenCode Go, the subscription, meters a rolling 5 hour window, a weekly one from Monday to Monday in UTC and a monthly one anchored to the day you subscribed. Zen pay-as-you-go credits are a different thing, and only the web dashboard shows them.",
        builtIn: {
            sub: "Open the dashboard.",
            link: { href: "https://opencode.ai", label: "Open opencode.ai" },
            body: "The dashboard shows the Go windows and your Zen credits. Nothing in the CLI does.",
        },
        windows: [
            { name: "5h", body: "A rolling window." },
            { name: "Weekly", body: "Monday to Monday, UTC." },
            { name: "Monthly", body: "Anchored to your subscription date." },
        ],
        signIn: "Notchlet reads the key OpenCode saved after /connect in ~/.local/share/opencode/auth.json and calls the Go usage endpoint with it, the same key the CLI sends. The key never expires, so a rejected key means you rotated it and need to reconnect. If your data directory moved or the CLI is not on this Mac, paste a key from the dashboard in Notchlet's settings.",
        faq: [
            {
                q: "Does Notchlet show Zen credits?",
                a: "No. Credits only exist on the web dashboard behind a browser session, and Notchlet does not borrow browser cookies. A workspace without a Go subscription shows nothing for OpenCode.",
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
