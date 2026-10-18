import { describe, expect, it } from "vitest";

import { guideFor, labelFor, providerFor } from "./guides";

describe("guideFor", () => {
    it("matches a rule id by its vendor prefix", () => {
        expect(guideFor("stripe-access-token")?.name).toBe("Stripe");
        expect(guideFor("github-fine-grained-pat")?.name).toBe("GitHub");
    });

    it("prefers the longest prefix so a specific rule beats its vendor", () => {
        expect(guideFor("slack-webhook-url")?.kind).toBe("webhook");
        expect(guideFor("slack-bot-token")?.kind).toBeUndefined();
        expect(guideFor("gcp-service-account")?.kind).toBe("keypair");
        expect(guideFor("gcp-api-key")?.kind).toBeUndefined();
    });

    it("only matches on a word boundary", () => {
        expect(guideFor("awsome-token")).toBeUndefined();
        expect(guideFor("aws-access-token")?.name).toBe("AWS");
    });

    it("returns nothing for a vendor that is not in the table", () => {
        expect(guideFor("zuplo-consumer-api-key.1")).toBeUndefined();
    });
});

describe("labelFor", () => {
    it.each([
        ["stripe-access-token", "Stripe access token"],
        ["openai-api-key", "OpenAI API key"],
        ["github-pat", "GitHub PAT"],
        ["aws-access-token", "AWS access token"],
        ["gcp-service-account", "Google Cloud service account key"],
        ["private-key", "private key"],
        ["jwt", "JWT"],
        ["pinecone-api-key.2", "Pinecone API key"],
        ["zuplo-consumer-api-key.1", "Zuplo consumer API key"],
        ["canadian-digital-service-notify-api-key", "Canadian digital service notify API key"],
    ])("%s reads as %s", (ruleId, label) => {
        expect(labelFor(ruleId)).toBe(label);
    });
});

describe("providerFor", () => {
    it("knows Notchlet's provider ids and nothing else", () => {
        expect(providerFor("claude-code")?.name).toBe("Claude Code");
        expect(providerFor("codex")?.company).toBe("OpenAI");
        expect(providerFor("cursor")).toBeUndefined();
        expect(providerFor(undefined)).toBeUndefined();
    });
});
