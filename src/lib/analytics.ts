import posthog from "posthog-js";

/**
 * The product analytics catalog. Every custom PostHog event this app can send is declared here, so event names and
 * properties stay consistent and discoverable. Add new events to this map, never call posthog.capture from components.
 *
 * Keep properties anonymous and small: counts and flags, not user content.
 */
type AnalyticsEvents = {
    /** Someone joined the launch waitlist from the download dialog. No properties: the email must not reach PostHog. */
    launch_signup: Record<string, never>;
};

export function track<Name extends keyof AnalyticsEvents>(
    name: Name,
    ...args: AnalyticsEvents[Name] extends Record<string, never> ? [] : [properties: AnalyticsEvents[Name]]
) {
    // posthog.capture is a safe no-op when PostHog was not initialized (no key).
    posthog.capture(name, args[0]);
}
