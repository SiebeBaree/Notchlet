import { ArrowUpRight } from "lucide-react";
import type { ReactNode } from "react";

import { Code, Section } from "@/components/article";

import { type Guide, guideFor, labelFor, providerFor, type SecretKind } from "../guides";

type Step = { title: string; body: ReactNode };

// The article a Notchlet user lands on after clicking "How to solve this". The rule tells us which vendor and what
// kind of secret, the provider tells us which chat file it sits in. Both are optional: the page has to hold up for
// someone who typed the URL.
export function SecretsFound({ rule, provider: providerId }: { rule?: string; provider?: string }) {
    const guide = rule === undefined ? undefined : guideFor(rule);
    const label = rule === undefined ? "key" : labelFor(rule);
    const provider = providerFor(providerId);
    const kind = guide?.kind ?? "key";
    const steps =
        kind === "public"
            ? publicSteps(label)
            : [...rotation[kind](guide), damageStep(guide), ...notchletStep(provider)];

    return (
        <article className="bg-white">
            <header className="relative overflow-hidden px-6 pt-40 pb-20">
                <div
                    aria-hidden
                    className="absolute inset-0 bg-[radial-gradient(60%_60%_at_50%_0%,#efeafd,transparent_70%)]"
                />
                <div className="relative mx-auto max-w-3xl">
                    <p className="font-mono text-[12px] font-medium text-brand">
                        {rule === undefined ? "Leaked secret" : label}
                        {provider && <span className="text-ink-3"> · {provider.name} chat</span>}
                    </p>
                    <h1 className="mt-5 font-display text-[42px] leading-[1.08] tracking-[-0.005em] text-balance text-ink sm:text-[60px]">
                        One of your secrets got leaked, what now?
                    </h1>
                    <p className="mt-6 max-w-xl text-[15px] leading-relaxed text-ink-3">
                        Notchlet found {article(label)} {label} in{" "}
                        {provider ? `a ${provider.name} chat` : "one of your AI chats"} on this Mac. It is fixable in
                        about ten minutes. Do the steps in order.
                    </p>
                </div>
            </header>

            <Section title="What happened." sub="And what did not.">
                <p>
                    Somewhere in a chat the key ended up in plain text. You pasted a <Code>.env</Code>, or the agent ran{" "}
                    <Code>cat .env</Code> or a curl with the key in a header, and the output landed in the transcript.{" "}
                    {provider ? (
                        <>
                            {provider.name} writes every transcript to <Code>{provider.path}</Code> and sent the
                            conversation to {provider.company} to get an answer.
                        </>
                    ) : (
                        <>
                            The CLI writes every transcript to disk and sent the conversation to its maker to get an
                            answer.
                        </>
                    )}{" "}
                    So the key now lives in two places you do not control much: a file on this disk and a log on their
                    servers.
                </p>
                <p>
                    Nobody at {provider?.company ?? "an AI lab"} is going to use it. Treat it as burned anyway. A new
                    key costs nothing, and the old one might also be in a Time Machine backup, a shared session or a
                    screenshot you forgot about. Rotating takes ten minutes. Finding out someone used it takes a lot
                    longer.
                </p>
                <p>
                    Notchlet read the file on your Mac and hashed what it found. The key never left the machine and
                    Notchlet does not keep it either, only the first six and last two characters so you can tell which
                    one it is.
                </p>
            </Section>

            <Section title="The fix." sub={fixSubtitle[kind]}>
                <ol className="divide-y divide-line">
                    {steps.map((step, index) => (
                        <li
                            key={step.title}
                            className="grid gap-3 py-8 first:pt-0 last:pb-0 sm:grid-cols-[72px_1fr] sm:gap-0"
                        >
                            <span className="font-mono text-[11px] font-medium text-brand sm:pt-1">
                                {String(index + 1).padStart(2, "0")}
                            </span>
                            <div>
                                <h3 className="text-[17px] font-semibold tracking-tight text-ink">{step.title}</h3>
                                <div className="mt-2.5 flex flex-col gap-3 text-[15px] leading-relaxed text-ink-2">
                                    {step.body}
                                </div>
                            </div>
                        </li>
                    ))}
                </ol>
            </Section>

            <Section title="Next time." sub="The key never enters the chat.">
                <p>
                    Do not paste a key into a chat. Put it in <Code>.env</Code> yourself and tell the agent the variable
                    name. <Code>STRIPE_SECRET_KEY</Code> is all it needs to write the code.
                </p>
                <p>
                    Stop Claude Code from opening the file. Add this to <Code>.claude/settings.json</Code> in the
                    project, or to <Code>~/.claude/settings.json</Code> for every project:
                </p>
                <pre className="overflow-x-auto rounded-lg border border-line bg-[#faf9fc] p-4 font-mono text-[13px] leading-relaxed text-ink">
                    {`{\n    "permissions": {\n        "deny": ["Read(./.env)", "Read(./.env.*)"]\n    }\n}`}
                </pre>
                <p>
                    Claude Code then refuses to read those files with its own tools. It can still run <Code>cat</Code>{" "}
                    in a terminal, so when a command touches <Code>.env</Code>, say no.
                </p>
                <p>
                    Build with test keys. Stripe, Twilio and most payment or email services have a test mode whose keys
                    move nothing real. Switch to live keys at deploy time, in the hosting dashboard, never in the chat.
                </p>
            </Section>
        </article>
    );
}

const fixSubtitle: Record<SecretKind, string> = {
    key: "Make a new one, swap it in, kill the old one.",
    keypair: "Make a new one, swap it in, kill the old one.",
    webhook: "Make a new one, swap it in, kill the old one.",
    password: "Change it, then update it everywhere.",
    session: "Sign out, then look around.",
    public: "Shorter than usual.",
};

function ExternalLink({ href, children }: { href: string; children: ReactNode }) {
    return (
        <a
            href={href}
            target="_blank"
            rel="noreferrer"
            className="inline-flex w-fit items-center gap-1.5 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-ink-2"
        >
            {children}
            <ArrowUpRight aria-hidden className="size-4" />
        </a>
    );
}

// "an OpenAI key", "an AWS key", "a Stripe key". Acronyms take "an" when the letter is said with a vowel sound.
function article(label: string) {
    return /^[aeiouAEIOU]|^[AEFHILMNORSX](?=[A-Z\s])|^x(?=[A-Z])/.test(label) ? "an" : "a";
}

// Where to make a new key, as a button when we know the page and as directions when we do not.
function rotateLink(guide: Guide | undefined) {
    if (guide?.rotate) {
        return (
            <ExternalLink href={guide.rotate.href}>
                Open {guide.name}: {guide.rotate.label}
            </ExternalLink>
        );
    }
    return (
        <p>
            Sign in to the service the key belongs to{guide ? ` (${guide.name})` : ""}. Look under Settings for
            something called API keys, Tokens, Developer or Credentials.
        </p>
    );
}

const rotation: Record<Exclude<SecretKind, "public">, (guide: Guide | undefined) => Step[]> = {
    key: (guide) => [
        {
            title: "Make a new key",
            body: (
                <>
                    <p>
                        Make a new key with the same permissions as the old one and copy it somewhere for a minute. If
                        the page has a Roll or Regenerate button, use it: that is steps one and three in one click.
                    </p>
                    {guide?.note && <p>{guide.note}</p>}
                    {rotateLink(guide)}
                </>
            ),
        },
        {
            title: "Put it where the old one was",
            body: (
                <>
                    <p>
                        The old key is in at least one place: a <Code>.env</Code> file, a hosting dashboard (Vercel,
                        Netlify, Railway and Render all call it Environment Variables), a GitHub Actions secret or a
                        config file. Swap each one and redeploy.
                    </p>
                    <p>
                        Not sure where it lives? Search the project for the first characters Notchlet showed you. In VS
                        Code and Cursor that is Cmd Shift F.
                    </p>
                </>
            ),
        },
        {
            title: "Delete the old key",
            body: (
                <p>
                    Once the new one works, go back and delete the old one. Not disable, delete. If you cannot tell
                    whether something still uses it, delete it anyway and see what breaks. A broken deploy is a five
                    minute fix. A stranger's usage on your card is not.
                </p>
            ),
        },
    ],
    keypair: (guide) => [
        {
            title: "Make a new pair",
            body: (
                <>
                    <p>{guide?.note ?? "Generate a new key pair the same way you made the old one."}</p>
                    {guide?.rotate && rotateLink(guide)}
                </>
            ),
        },
        {
            title: "Put the new private key where the old one was",
            body: (
                <p>
                    <Code>~/.ssh</Code> on this Mac, a CI secret, a server. Register the new public half everywhere the
                    old one was registered.
                </p>
            ),
        },
        {
            title: "Remove the old public key",
            body: (
                <p>
                    GitHub under Settings, SSH and GPG keys. Every server's <Code>authorized_keys</Code>. The service
                    account or certificate authority. Then delete the old private key file.
                </p>
            ),
        },
    ],
    password: (guide) => [
        {
            title: "Change the password",
            body: (
                <>
                    <p>
                        {guide?.note ??
                            "Change the password on the account the string belongs to. The old string dies with it."}
                    </p>
                    {guide?.rotate && rotateLink(guide)}
                </>
            ),
        },
        {
            title: "Update it everywhere",
            body: (
                <p>
                    Paste the new connection string into every <Code>.env</Code>, hosting dashboard and CI secret that
                    had the old one, then redeploy. Search the project for the first characters Notchlet showed you if
                    you are not sure where.
                </p>
            ),
        },
    ],
    session: (guide) => [
        {
            title: "Sign out everywhere",
            body: (
                <>
                    <p>{guide?.note ?? "This is a login token, not a key. It dies when the session does."}</p>
                    {guide?.rotate && rotateLink(guide)}
                </>
            ),
        },
    ],
    webhook: (guide) => [
        {
            title: "Make a new webhook",
            body: (
                <>
                    <p>
                        A webhook URL is a secret: anyone who has it can post into that channel. Delete this one and
                        create a fresh one in the same place.
                    </p>
                    {guide?.note && <p>{guide.note}</p>}
                    {guide?.rotate && rotateLink(guide)}
                </>
            ),
        },
        {
            title: "Paste the new URL where the old one was",
            body: (
                <p>
                    Whatever posts to the channel has the old URL in a config or a secret. Swap it and send a test
                    message.
                </p>
            ),
        },
    ],
};

function damageStep(guide: Guide | undefined): Step {
    return {
        title: "Look for damage",
        body: (
            <>
                <p>
                    Open the usage, billing or logs page and look for anything since the chat you do not recognize:
                    requests from places you have never been, spend you did not cause, new users or keys you did not
                    make.
                </p>
                <p>
                    Found something? Email their support today, say the key leaked and ask for the charges to be
                    reversed. They have a process for this.
                </p>
                {guide?.activity && (
                    <ExternalLink href={guide.activity.href}>
                        Open {guide.name}: {guide.activity.label}
                    </ExternalLink>
                )}
            </>
        ),
    };
}

function notchletStep(provider: ReturnType<typeof providerFor>): Step[] {
    return [
        {
            title: "Tell Notchlet",
            body: (
                <>
                    <p>
                        Hover the notch and hit Ignore on this key. Notchlet remembers it by its hash and stays quiet
                        about it, even when the same key turns up in another chat.
                    </p>
                    <p>
                        Deleting the transcript is optional. A dead key in a file opens nothing.
                        {provider && (
                            <>
                                {" "}
                                If you want it gone anyway, the chats are in <Code>{provider.path}</Code>
                                {provider.name === "Claude Code" &&
                                    ", and Claude Code deletes them itself after 30 days"}
                                .
                            </>
                        )}
                    </p>
                </>
            ),
        },
    ];
}

// Identifiers betterleaks reports because they usually sit next to a real secret: an Algolia app id, a Supabase
// project URL. There is nothing to rotate.
function publicSteps(label: string): Step[] {
    return [
        {
            title: "This one is not a secret",
            body: (
                <p>
                    {article(label) === "an" ? "An" : "A"} {label} is meant to be visible. It got flagged because it
                    usually sits right next to a key that is not. Check the other findings in Notchlet and the rest of
                    that chat.
                </p>
            ),
        },
        ...notchletStep(undefined),
    ];
}
