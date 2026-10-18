import { ArrowUpRight } from "lucide-react";
import type { ReactNode } from "react";

import { ArticleHeader, Code, Section } from "@/components/article";

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
        <article className="mx-auto max-w-7xl border-x border-line bg-white sm:mx-6 xl:mx-auto">
            <ArticleHeader title="Notchlet found a possible secret in your chats.">
                <p>
                    Review the {label} found in {provider ? `a ${provider.name} chat` : "your chat history"}. If it is
                    an active credential, follow the steps below to replace it.
                </p>
            </ArticleHeader>

            <Section title="Review the finding">
                <p>
                    A credential can end up in a transcript when you paste a <Code>.env</Code> file or an agent prints a
                    command containing it. The conversation may also have been sent to your AI provider. Notchlet cannot
                    tell whether the credential is still active or has been used by someone else.
                </p>
                <p>
                    Check the matched text in Notchlet. If it is a real credential, replace it and revoke the old one.
                    It may also appear in backups, shared sessions or screenshots.
                </p>
                <p>
                    Notchlet scans files locally. It stores a hash and the first six and last two characters of a
                    finding so you can identify it. It does not send findings to a server or test credentials against
                    provider APIs.
                </p>
            </Section>

            <Section title="Resolve the finding" sub={fixSubtitle[kind]}>
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

            <Section title="Keep credentials out of chats">
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
                    Use sandbox credentials during development when the service provides them. Add production
                    credentials through your hosting dashboard or secret manager. Keep both out of chat messages.
                </p>
            </Section>
        </article>
    );
}

const fixSubtitle: Record<SecretKind, string> = {
    key: "Replace the key and revoke the old one.",
    keypair: "Replace the key pair and remove the old authorization.",
    webhook: "Replace the webhook URL.",
    password: "Change the password and update the connections that use it.",
    session: "Revoke the session and check account activity.",
    public: "This identifier is intended to be public. Check nearby findings for credentials.",
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
                        Create a replacement key with only the permissions your app needs. Store it in your secret
                        manager or environment configuration. Check the service's rotation instructions before using a
                        Roll or Regenerate action, since it may revoke the old key immediately.
                    </p>
                    {guide?.note && <p>{guide.note}</p>}
                    {rotateLink(guide)}
                </>
            ),
        },
        {
            title: "Update the apps that use it",
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
                    After updating the apps that use the key, verify they work and revoke the old credential. If you
                    suspect someone is actively using the exposed key, revoke it immediately and restore affected
                    services with the replacement.
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
                    If you find unfamiliar activity, contact the service's support team. Include the affected credential
                    identifier and dates, but do not send the credential itself.
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
            title: "Dismiss the resolved finding",
            body: (
                <>
                    <p>
                        Once the credential has been revoked, choose Ignore in Notchlet. It remembers the finding by its
                        hash and will not alert you again for the same value.
                    </p>
                    <p>
                        Deleting a transcript does not revoke the credential. After revoking it, you can also remove
                        local copies.
                        {provider && (
                            <>
                                {" "}
                                The chats are in <Code>{provider.path}</Code>.
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
                    {article(label) === "an" ? "An" : "A"} {label} is meant to be visible. It may have been flagged
                    alongside a private credential. Check the other findings in Notchlet and the surrounding chat before
                    dismissing it.
                </p>
            ),
        },
        {
            title: "Dismiss the finding",
            body: (
                <p>
                    After checking the surrounding chat for private credentials, choose Ignore on this public identifier
                    in Notchlet.
                </p>
            ),
        },
    ];
}
