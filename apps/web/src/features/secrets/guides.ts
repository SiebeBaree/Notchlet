// What the page knows about each kind of leaked secret. Notchlet opens /secrets-found?rule=<betterleaks rule id>,
// and the rule id starts with the vendor (aws-access-token, github-pat, slack-webhook-url). Guides are keyed by
// rule id prefix; the longest match wins so slack-webhook-url beats slack. betterleaks ships ~350 high confidence
// rules and most vendors are not here on purpose: a wrong dashboard link is worse than "open the vendor's
// settings", which is what the fallback says.

/** How you kill this kind of secret. Changes what step one tells the reader to do. */
export type SecretKind = "key" | "keypair" | "password" | "session" | "webhook" | "public";

export type Guide = {
    /** The vendor as the reader knows it. */
    name: string;
    /** What to call the secret when the prefix is the whole rule id and the vendor name alone would not do. */
    label?: string;
    /** Where new keys are made and old ones deleted. */
    rotate?: { href: string; label: string };
    /** Where the vendor shows what the key did. */
    activity?: { href: string; label: string };
    /** One thing about this key the generic steps get wrong. */
    note?: string;
    kind?: SecretKind;
};

const guides: Record<string, Guide> = {
    "1password": {
        name: "1Password",
        rotate: {
            href: "https://my.1password.com/developer-tools/infrastructure-secrets/serviceaccount",
            label: "Developer, Service accounts",
        },
    },
    adobe: { name: "Adobe", rotate: { href: "https://developer.adobe.com/console", label: "Adobe Developer Console" } },
    "age-secret-key": {
        name: "age",
        label: "age secret key",
        kind: "keypair",
        note: "Run age-keygen for a new pair, re-encrypt every file with the new recipient and delete the old identity file.",
    },
    airtable: {
        name: "Airtable",
        rotate: { href: "https://airtable.com/create/tokens", label: "Personal access tokens" },
    },
    algolia: { name: "Algolia", rotate: { href: "https://dashboard.algolia.com/account/api-keys", label: "API keys" } },
    "algolia-application-id": { name: "Algolia", label: "Algolia application ID", kind: "public" },
    alibaba: {
        name: "Alibaba Cloud",
        rotate: { href: "https://ram.console.aliyun.com/manage/ak", label: "RAM, AccessKey" },
    },
    anthropic: {
        name: "Anthropic",
        rotate: { href: "https://console.anthropic.com/settings/keys", label: "Console, API keys" },
        activity: { href: "https://console.anthropic.com/settings/logs", label: "Console, Logs" },
        note: "This is a console API key, billed per token. Your Claude Code login is a different thing and is not affected.",
    },
    "anthropic-admin-api-key": {
        name: "Anthropic",
        label: "Anthropic admin API key",
        rotate: { href: "https://console.anthropic.com/settings/admin-keys", label: "Console, Admin keys" },
        note: "An admin key can create other keys and change who is in the organization. Treat it like the root password.",
    },
    apify: {
        name: "Apify",
        rotate: { href: "https://console.apify.com/account/integrations", label: "Account, Integrations" },
    },
    asana: { name: "Asana", rotate: { href: "https://app.asana.com/0/my-apps", label: "My apps" } },
    atlassian: {
        name: "Atlassian",
        rotate: { href: "https://id.atlassian.com/manage-profile/security/api-tokens", label: "Account, API tokens" },
    },
    aws: {
        name: "AWS",
        rotate: { href: "https://console.aws.amazon.com/iam/home#/users", label: "IAM, Users, Security credentials" },
        activity: { href: "https://console.aws.amazon.com/cloudtrail/home#/events", label: "CloudTrail event history" },
        note: "An access key comes as a pair, the AKIA id and the secret. Make a new pair, then deactivate the old one before you delete it so you can undo if something breaks. Also open Billing: a leaked AWS key is what people use to mine crypto on your card.",
    },
    "aws-amazon-bedrock": {
        name: "AWS Bedrock",
        rotate: { href: "https://console.aws.amazon.com/iam/home#/users", label: "IAM, Users, Security credentials" },
        activity: { href: "https://console.aws.amazon.com/billing/home", label: "Billing" },
    },
    azure: {
        name: "Azure",
        rotate: { href: "https://portal.azure.com", label: "Azure portal" },
        note: "Client secrets live under the app registration, Certificates & secrets. Storage and Service Bus keys have a Rotate button under Access keys. Connection strings embed the key, so rotate the key and copy the new string.",
    },
    bitbucket: {
        name: "Bitbucket",
        rotate: { href: "https://bitbucket.org/account/settings/app-passwords/", label: "App passwords" },
    },
    bitly: { name: "Bitly", rotate: { href: "https://app.bitly.com/settings/api/", label: "Settings, API" } },
    buildkite: {
        name: "Buildkite",
        rotate: { href: "https://buildkite.com/user/api-access-tokens", label: "API access tokens" },
    },
    cerebras: { name: "Cerebras", rotate: { href: "https://cloud.cerebras.ai/platform", label: "Platform, API keys" } },
    circleci: {
        name: "CircleCI",
        rotate: { href: "https://app.circleci.com/settings/user/tokens", label: "Personal API tokens" },
    },
    cloudflare: {
        name: "Cloudflare",
        rotate: { href: "https://dash.cloudflare.com/profile/api-tokens", label: "Profile, API tokens" },
        note: "The Global API Key cannot be deleted, only rolled. It has every permission on every zone.",
    },
    cloudinary: {
        name: "Cloudinary",
        rotate: { href: "https://console.cloudinary.com/settings/api-keys", label: "Settings, API keys" },
    },
    "cloudinary-cloud-name": { name: "Cloudinary", label: "Cloudinary cloud name", kind: "public" },
    confluent: {
        name: "Confluent",
        rotate: { href: "https://confluent.cloud/settings/api-keys", label: "Settings, API keys" },
    },
    "crates-io": {
        name: "crates.io",
        rotate: { href: "https://crates.io/settings/tokens", label: "Settings, API tokens" },
    },
    "curl-auth-user": {
        name: "curl",
        label: "curl password",
        kind: "password",
        note: "The leaked part is a username and password on a curl command. Change that password wherever that account lives.",
    },
    datadog: {
        name: "Datadog",
        rotate: {
            href: "https://app.datadoghq.com/organization-settings/api-keys",
            label: "Organization settings, API keys",
        },
    },
    deepgram: { name: "Deepgram", rotate: { href: "https://console.deepgram.com", label: "Console, API keys" } },
    deepseek: {
        name: "DeepSeek",
        rotate: { href: "https://platform.deepseek.com/api_keys", label: "Platform, API keys" },
    },
    deno: {
        name: "Deno Deploy",
        rotate: { href: "https://dash.deno.com/account#access-tokens", label: "Account, Access tokens" },
    },
    digitalocean: {
        name: "DigitalOcean",
        rotate: { href: "https://cloud.digitalocean.com/account/api/tokens", label: "API, Tokens" },
    },
    "docker-swarm": {
        name: "Docker Swarm",
        note: "On a manager node run docker swarm join-token --rotate worker (and manager), or docker swarm unlock-key --rotate for the unlock key.",
    },
    dockerhub: {
        name: "Docker Hub",
        rotate: {
            href: "https://app.docker.com/settings/personal-access-tokens",
            label: "Settings, Personal access tokens",
        },
    },
    doppler: {
        name: "Doppler",
        rotate: { href: "https://dashboard.doppler.com", label: "Dashboard, the project's Access tab" },
    },
    dropbox: {
        name: "Dropbox",
        rotate: { href: "https://www.dropbox.com/developers/apps", label: "Developers, My apps" },
    },
    "elastic-cloud": {
        name: "Elastic Cloud",
        rotate: { href: "https://cloud.elastic.co/deployment-features/keys", label: "Organization, API keys" },
    },
    elevenlabs: {
        name: "ElevenLabs",
        rotate: { href: "https://elevenlabs.io/app/settings/api-keys", label: "Settings, API keys" },
    },
    facebook: {
        name: "Meta",
        rotate: { href: "https://developers.facebook.com/apps", label: "Meta for Developers, My apps" },
    },
    fastly: {
        name: "Fastly",
        rotate: { href: "https://manage.fastly.com/account/personal/tokens", label: "Account, Personal API tokens" },
    },
    figma: {
        name: "Figma",
        rotate: { href: "https://www.figma.com/settings", label: "Settings, Security, Personal access tokens" },
    },
    flutterwave: {
        name: "Flutterwave",
        rotate: { href: "https://app.flutterwave.com/dashboard/settings/apis", label: "Settings, API" },
    },
    "flutterwave-public-key": { name: "Flutterwave", label: "Flutterwave public key", kind: "public" },
    flyio: {
        name: "Fly.io",
        rotate: { href: "https://fly.io/user/personal_access_tokens", label: "Personal access tokens" },
    },
    gcp: {
        name: "Google Cloud",
        rotate: { href: "https://console.cloud.google.com/apis/credentials", label: "APIs & Services, Credentials" },
        activity: { href: "https://console.cloud.google.com/logs", label: "Logs Explorer" },
    },
    "gcp-service-account": {
        name: "Google Cloud",
        label: "Google Cloud service account key",
        kind: "keypair",
        rotate: {
            href: "https://console.cloud.google.com/iam-admin/serviceaccounts",
            label: "IAM, Service accounts, Keys",
        },
        activity: { href: "https://console.cloud.google.com/logs", label: "Logs Explorer" },
        note: "The leak is the JSON key file of a service account. Open the account, delete that key under Keys and add a new one. If the account was only for one experiment, delete the whole account.",
    },
    "gcp-application-default-credentials": {
        name: "Google Cloud",
        label: "Google Cloud login",
        kind: "session",
        rotate: { href: "https://myaccount.google.com/permissions", label: "Google account, Third-party access" },
        note: "This is your own gcloud login, stored by gcloud auth application-default login. Remove Google Cloud SDK from your account's third-party access, then log in again.",
    },
    "gcp-gemini-api": {
        name: "Google AI Studio",
        label: "Gemini API key",
        rotate: { href: "https://aistudio.google.com/app/apikey", label: "AI Studio, API keys" },
    },
    gitea: { name: "Gitea", note: "On your Gitea instance open Settings, Applications and delete the token there." },
    github: {
        name: "GitHub",
        rotate: {
            href: "https://github.com/settings/tokens",
            label: "Settings, Developer settings, Personal access tokens",
        },
        activity: { href: "https://github.com/settings/security-log", label: "Security log" },
        note: "A token starting with ghp_ or github_pat_ is yours to delete on the tokens page. gho_ came from an app you authorized, revoke it under Applications. ghs_ tokens expire on their own within an hour.",
    },
    gitlab: {
        name: "GitLab",
        rotate: {
            href: "https://gitlab.com/-/user_settings/personal_access_tokens",
            label: "User settings, Access tokens",
        },
        note: "Deploy, runner and project tokens live under the project or group, Settings, Access tokens, CI/CD or Runners.",
    },
    "gitlab-session-cookie": {
        name: "GitLab",
        label: "GitLab session cookie",
        kind: "session",
        rotate: { href: "https://gitlab.com/-/user_settings/active_sessions", label: "Active sessions" },
    },
    grafana: { name: "Grafana", rotate: { href: "https://grafana.com/orgs", label: "My account, Access policies" } },
    groq: { name: "Groq", rotate: { href: "https://console.groq.com/keys", label: "Console, API keys" } },
    gumroad: {
        name: "Gumroad",
        rotate: { href: "https://app.gumroad.com/settings/advanced", label: "Settings, Advanced" },
    },
    "hashicorp-tf": {
        name: "HCP Terraform",
        rotate: { href: "https://app.terraform.io/app/settings/tokens", label: "User settings, Tokens" },
    },
    heroku: {
        name: "Heroku",
        rotate: { href: "https://dashboard.heroku.com/account", label: "Account settings, API key" },
    },
    hubspot: {
        name: "HubSpot",
        rotate: { href: "https://app.hubspot.com", label: "Settings, Integrations, Private apps" },
    },
    huggingface: {
        name: "Hugging Face",
        rotate: { href: "https://huggingface.co/settings/tokens", label: "Settings, Access tokens" },
    },
    jwt: {
        name: "JWT",
        label: "JWT",
        kind: "session",
        note: "A JWT is a signed login token. If a website issued it, sign out of that website everywhere. If your own code signs them, change the signing secret. Every token made with the old secret stops working at once.",
    },
    kagi: { name: "Kagi", rotate: { href: "https://kagi.com/settings?p=api", label: "Settings, API" } },
    kimi: {
        name: "Moonshot",
        rotate: { href: "https://platform.moonshot.ai/console/api-keys", label: "Console, API keys" },
    },
    klaviyo: {
        name: "Klaviyo",
        rotate: { href: "https://www.klaviyo.com/settings/account/api-keys", label: "Settings, API keys" },
    },
    "kubernetes-secret-yaml": {
        name: "Kubernetes",
        label: "Kubernetes Secret",
        note: "The leak is whatever value sits inside the Secret manifest. Rotate that with its own vendor, then apply a new Secret. Deleting the file changes nothing in the cluster.",
    },
    "langchain-langsmith": {
        name: "LangSmith",
        rotate: { href: "https://smith.langchain.com/settings", label: "Settings, API keys" },
    },
    launchdarkly: {
        name: "LaunchDarkly",
        rotate: {
            href: "https://app.launchdarkly.com/settings/authorization",
            label: "Account settings, Authorization",
        },
    },
    linear: {
        name: "Linear",
        rotate: { href: "https://linear.app/settings/account/security", label: "Settings, Security & access" },
    },
    mailchimp: {
        name: "Mailchimp",
        rotate: { href: "https://admin.mailchimp.com/account/api/", label: "Account, Extras, API keys" },
    },
    mailersend: { name: "MailerSend", rotate: { href: "https://app.mailersend.com/api-tokens", label: "API tokens" } },
    mailgun: {
        name: "Mailgun",
        rotate: { href: "https://app.mailgun.com/settings/api_security", label: "Settings, API security" },
    },
    "mailgun-pub-key": { name: "Mailgun", label: "Mailgun public key", kind: "public" },
    mapbox: {
        name: "Mapbox",
        rotate: { href: "https://account.mapbox.com/access-tokens/", label: "Account, Access tokens" },
    },
    maxmind: {
        name: "MaxMind",
        rotate: { href: "https://www.maxmind.com/en/accounts/current/license-key", label: "Account, License keys" },
    },
    mercury: {
        name: "Mercury",
        rotate: { href: "https://app.mercury.com/settings/tokens", label: "Settings, API tokens" },
    },
    "microsoft-teams-webhook": {
        name: "Microsoft Teams",
        label: "Microsoft Teams webhook",
        kind: "webhook",
        note: "In the channel, open Workflows (or the Incoming Webhook connector on older tenants), remove it and create a new one.",
    },
    "mongodb-atlas": {
        name: "MongoDB Atlas",
        rotate: { href: "https://cloud.mongodb.com", label: "Organization, Access Manager, API keys" },
    },
    "mongodb-connection-string": {
        name: "MongoDB",
        label: "MongoDB connection string",
        kind: "password",
        rotate: { href: "https://cloud.mongodb.com", label: "Atlas, Database Access" },
        note: "The password is inside the connection string, right after the username. Change the database user's password and paste the new string wherever the old one was.",
    },
    neon: {
        name: "Neon",
        rotate: { href: "https://console.neon.tech/app/settings/api-keys", label: "Account settings, API keys" },
    },
    netlify: {
        name: "Netlify",
        rotate: { href: "https://app.netlify.com/user/applications", label: "User settings, Applications" },
    },
    "new-relic": { name: "New Relic", rotate: { href: "https://one.newrelic.com/api-keys", label: "API keys" } },
    notion: {
        name: "Notion",
        rotate: { href: "https://www.notion.so/profile/integrations", label: "My integrations" },
    },
    npm: { name: "npm", rotate: { href: "https://www.npmjs.com", label: "Profile, Access tokens" } },
    nuget: { name: "NuGet", rotate: { href: "https://www.nuget.org/account/apikeys", label: "Account, API keys" } },
    nvidia: { name: "NVIDIA", rotate: { href: "https://build.nvidia.com", label: "build.nvidia.com, API keys" } },
    ollama: { name: "Ollama", rotate: { href: "https://ollama.com/settings/keys", label: "Settings, Keys" } },
    openai: {
        name: "OpenAI",
        rotate: { href: "https://platform.openai.com/api-keys", label: "Platform, API keys" },
        activity: { href: "https://platform.openai.com/usage", label: "Platform, Usage" },
        note: "This is a platform API key, billed per token. Your ChatGPT or Codex login is a different thing and is not affected.",
    },
    openrouter: {
        name: "OpenRouter",
        rotate: { href: "https://openrouter.ai/settings/keys", label: "Settings, Keys" },
        activity: { href: "https://openrouter.ai/activity", label: "Activity" },
    },
    perplexity: {
        name: "Perplexity",
        rotate: { href: "https://www.perplexity.ai/settings/api", label: "Settings, API" },
    },
    pinecone: { name: "Pinecone", rotate: { href: "https://app.pinecone.io", label: "Console, API keys" } },
    pkcs12: {
        name: "PKCS#12",
        kind: "keypair",
        note: "A .p12 or .pfx file holds a private key and its certificate. Reissue the certificate with a new key and revoke the old one with whoever issued it.",
    },
    plaid: {
        name: "Plaid",
        rotate: { href: "https://dashboard.plaid.com/developers/keys", label: "Developers, Keys" },
    },
    planetscale: {
        name: "PlanetScale",
        rotate: { href: "https://app.planetscale.com", label: "Database, Settings, Passwords" },
    },
    "planetscale-password": {
        name: "PlanetScale",
        label: "PlanetScale password",
        kind: "password",
        rotate: { href: "https://app.planetscale.com", label: "Database, Settings, Passwords" },
    },
    polar: { name: "Polar", rotate: { href: "https://polar.sh/settings", label: "Settings, Access tokens" } },
    posthog: {
        name: "PostHog",
        rotate: { href: "https://app.posthog.com/settings/user-api-keys", label: "Settings, Personal API keys" },
    },
    postman: {
        name: "Postman",
        rotate: { href: "https://web.postman.co/settings/me/api-keys", label: "Settings, API keys" },
    },
    "private-key": {
        name: "Private key",
        label: "private key",
        kind: "keypair",
        note: "A PEM block is usually an SSH key or a TLS key. For SSH: ssh-keygen a new pair, add the new public key where the old one was (GitHub Settings, SSH keys, or a server's authorized_keys), then remove the old public key. For TLS: reissue the certificate with a new key.",
    },
    pulumi: {
        name: "Pulumi",
        rotate: { href: "https://app.pulumi.com/account/tokens", label: "Account, Access tokens" },
    },
    pypi: { name: "PyPI", rotate: { href: "https://pypi.org/manage/account/", label: "Account settings, API tokens" } },
    rapidapi: {
        name: "RapidAPI",
        rotate: { href: "https://rapidapi.com/developer/apps", label: "Developer dashboard, Apps" },
    },
    render: {
        name: "Render",
        rotate: { href: "https://dashboard.render.com/u/settings#api-keys", label: "Account settings, API keys" },
    },
    replicate: {
        name: "Replicate",
        rotate: { href: "https://replicate.com/account/api-tokens", label: "Account, API tokens" },
    },
    rubygems: {
        name: "RubyGems",
        rotate: { href: "https://rubygems.org/profile/api_keys", label: "Profile, API keys" },
    },
    runpod: {
        name: "RunPod",
        rotate: { href: "https://www.runpod.io/console/user/settings", label: "Settings, API keys" },
    },
    scaleway: {
        name: "Scaleway",
        rotate: { href: "https://console.scaleway.com/iam/api-keys", label: "IAM, API keys" },
    },
    sendgrid: {
        name: "SendGrid",
        rotate: { href: "https://app.sendgrid.com/settings/api_keys", label: "Settings, API keys" },
    },
    sendinblue: {
        name: "Brevo",
        rotate: { href: "https://app.brevo.com/settings/keys/api", label: "SMTP & API, API keys" },
    },
    sentry: {
        name: "Sentry",
        rotate: { href: "https://sentry.io/settings/account/api/auth-tokens/", label: "Account, Auth tokens" },
    },
    shopify: {
        name: "Shopify",
        rotate: { href: "https://admin.shopify.com", label: "Settings, Apps and sales channels, Develop apps" },
    },
    "sidekiq-sensitive-url": {
        name: "Sidekiq",
        label: "Sidekiq Redis URL",
        kind: "password",
        note: "The URL carries a Redis password. Change it on the Redis side and update the URL.",
    },
    slack: {
        name: "Slack",
        rotate: { href: "https://api.slack.com/apps", label: "Your apps, OAuth & Permissions" },
        note: "Pick the app the token belongs to and hit Revoke under OAuth & Permissions, then reinstall to get a fresh one.",
    },
    "slack-webhook-url": {
        name: "Slack",
        label: "Slack webhook URL",
        kind: "webhook",
        rotate: { href: "https://api.slack.com/apps", label: "Your apps, Incoming Webhooks" },
    },
    "slack-session": {
        name: "Slack",
        kind: "session",
        rotate: { href: "https://slack.com/signout", label: "Sign out of Slack everywhere" },
    },
    snyk: { name: "Snyk", rotate: { href: "https://app.snyk.io/account", label: "Account settings, API token" } },
    sonar: {
        name: "SonarQube Cloud",
        rotate: { href: "https://sonarcloud.io/account/security", label: "My account, Security" },
    },
    square: {
        name: "Square",
        rotate: { href: "https://developer.squareup.com/apps", label: "Developer dashboard, Credentials" },
    },
    stripe: {
        name: "Stripe",
        rotate: { href: "https://dashboard.stripe.com/apikeys", label: "Developers, API keys" },
        activity: { href: "https://dashboard.stripe.com/logs", label: "Developers, Logs" },
        note: "sk_test keys move fake money and can wait. sk_live and rk_live are the real ones. Use Roll key: it makes the new key and gives the old one a few hours to die.",
    },
    supabase: {
        name: "Supabase",
        rotate: {
            href: "https://supabase.com/dashboard/project/_/settings/api-keys",
            label: "Project settings, API keys",
        },
        note: "The anon or publishable key is meant to ship in your app and is fine. service_role and sb_secret keys skip every row level security policy, rotate those.",
    },
    "supabase-management-token": {
        name: "Supabase",
        label: "Supabase access token",
        rotate: { href: "https://supabase.com/dashboard/account/tokens", label: "Account, Access tokens" },
    },
    "supabase-project-url": { name: "Supabase", label: "Supabase project URL", kind: "public" },
    tailscale: {
        name: "Tailscale",
        rotate: { href: "https://login.tailscale.com/admin/settings/keys", label: "Admin console, Keys" },
    },
    "telegram-bot": {
        name: "Telegram",
        rotate: { href: "https://t.me/BotFather", label: "BotFather" },
        note: "Send /revoke to BotFather, pick the bot, and it hands you a new token.",
    },
    togetherai: {
        name: "Together AI",
        rotate: { href: "https://api.together.ai/settings/api-keys", label: "Settings, API keys" },
    },
    twilio: {
        name: "Twilio",
        rotate: {
            href: "https://console.twilio.com/us1/account/keys-credentials/api-keys",
            label: "Account, API keys & tokens",
        },
    },
    twitter: {
        name: "X",
        rotate: { href: "https://developer.x.com/en/portal/dashboard", label: "Developer portal, Keys and tokens" },
    },
    typeform: {
        name: "Typeform",
        rotate: { href: "https://admin.typeform.com/user/tokens", label: "Personal tokens" },
    },
    unkey: {
        name: "Unkey",
        rotate: { href: "https://app.unkey.com/settings/root-keys", label: "Settings, Root keys" },
    },
    "val-town": {
        name: "Val Town",
        rotate: { href: "https://www.val.town/settings/api", label: "Settings, API tokens" },
    },
    vault: {
        name: "HashiCorp Vault",
        kind: "session",
        note: "Run vault token revoke with the token, or revoke it from the UI under Access.",
    },
    vercel: {
        name: "Vercel",
        rotate: { href: "https://vercel.com/account/settings/tokens", label: "Account settings, Tokens" },
        activity: { href: "https://vercel.com/account/settings/activity", label: "Activity log" },
    },
    "vercel-ai-gateway-key": {
        name: "Vercel AI Gateway",
        label: "Vercel AI Gateway key",
        rotate: { href: "https://vercel.com/ai-gateway", label: "AI Gateway, API keys" },
    },
    wakatime: {
        name: "WakaTime",
        rotate: { href: "https://wakatime.com/settings/api-key", label: "Settings, API key" },
    },
    "weights-and-biases": {
        name: "Weights & Biases",
        rotate: { href: "https://wandb.ai/settings", label: "Settings, API keys" },
    },
    workos: { name: "WorkOS", rotate: { href: "https://dashboard.workos.com/api-keys", label: "Dashboard, API keys" } },
    xai: { name: "xAI", rotate: { href: "https://console.x.ai", label: "Console, API keys" } },
    zendesk: {
        name: "Zendesk",
        rotate: { href: "https://www.zendesk.com", label: "Admin Center, Apps and integrations, APIs" },
    },
};

const guidePrefixes = Object.keys(guides).toSorted((a, b) => b.length - a.length);

function matchGuide(ruleId: string) {
    const prefix = guidePrefixes.find((candidate) => ruleId === candidate || ruleId.startsWith(`${candidate}-`));
    return prefix === undefined ? undefined : { prefix, guide: guides[prefix]! };
}

/** The guide for a betterleaks rule id, or undefined when the vendor is not in the table. */
export function guideFor(ruleId: string) {
    return matchGuide(ruleId)?.guide;
}

const acronyms = new Set([
    "api",
    "id",
    "sdk",
    "jwt",
    "pat",
    "url",
    "aws",
    "gcp",
    "ca",
    "eu",
    "us",
    "ci",
    "oauth",
    "sts",
]);

/**
 * A readable label for a rule id: "stripe-access-token" becomes "Stripe access token". The vendor prefix is swapped
 * for the vendor's real name when there is a guide, so "openai-api-key" reads "OpenAI API key" and not "Openai".
 * betterleaks numbers duplicate ids (pinecone-api-key.2); the suffix is dropped.
 */
export function labelFor(ruleId: string) {
    const id = ruleId.replace(/\.\d+$/, "");
    const match = matchGuide(id);
    const rest = (match === undefined ? id : id.slice(match.prefix.length))
        .split("-")
        .filter(Boolean)
        .map((word) => (acronyms.has(word) ? word.toUpperCase() : word));
    if (match === undefined) {
        const [first = "", ...others] = rest;
        return [first.charAt(0).toUpperCase() + first.slice(1), ...others].join(" ");
    }
    if (rest.length === 0) return match.guide.label ?? match.guide.name;
    return [match.guide.name, ...rest].join(" ");
}

/** Where the chats live for each Notchlet provider id, so the page can say which file the key sits in. */
export const providers = {
    "claude-code": { name: "Claude Code", company: "Anthropic", path: "~/.claude/projects" },
    codex: { name: "Codex", company: "OpenAI", path: "~/.codex/sessions" },
} as const;

export function providerFor(id: string | undefined) {
    return id !== undefined && id in providers ? providers[id as keyof typeof providers] : undefined;
}
