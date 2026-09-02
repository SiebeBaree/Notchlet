import Foundation
import PostHog

/// Thin wrapper around the PostHog SDK (EU cloud).
///
/// Everything is anonymous: a random UUID minted on first launch is the only
/// identity, `identify()` is never called and person profiles are disabled.
/// Analytics is off entirely in DEBUG builds so development never pollutes
/// the data, and the user can opt out in settings. Every call is a safe
/// no-op until `bootstrap()` runs.
enum Analytics {
    /// Public write-only project key from the PostHog project settings.
    /// Substituted into Info.plist at build time from Config/Secrets.xcconfig
    /// so it never lives in source. Empty in checkouts without that file,
    /// which leaves analytics off.
    private static var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String ?? ""
    }

    private static let host = "https://eu.i.posthog.com"

    private static let optOutKey = "analyticsOptOut"
    private static let distinctIDKey = "analyticsDistinctID"
    private static let lastRunVersionKey = "analyticsLastRunVersion"
    private static let lastHeartbeatDayKey = "analyticsLastHeartbeatDay"

    private static let launchedAt = Date()
    private static var isBootstrapped = false
    private static var heartbeatTimer: Timer?
    private static var providerContext: NSDictionary = [:]

    /// Whether the user shares anonymous usage stats. On by default; the
    /// settings toggle flips it.
    static var isEnabled: Bool {
        !UserDefaults.standard.bool(forKey: optOutKey)
    }

    static func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        UserDefaults.standard.set(!enabled, forKey: optOutKey)
        guard isBootstrapped else { return }
        if enabled {
            PostHogSDK.shared.optIn()
            capture(.settingChanged(key: "share_usage_stats", value: "true"))
        } else {
            // Respect the choice immediately; the flip itself is not sent.
            PostHogSDK.shared.optOut()
        }
    }

    /// Configures PostHog, registers the device context as super properties
    /// and fires the launch events. Call once at app launch.
    static func bootstrap() {
        #if DEBUG
        // Development builds never send analytics.
        #else
            guard !apiKey.isEmpty else { return }

            let distinctID = stableDistinctID()
            let config = PostHogConfig(apiKey: apiKey, host: host)
            config.personProfiles = .never
            config.captureApplicationLifecycleEvents = false
            // The SDK's flush timer fires whether or not anything is queued.
            // Events here are rare and nothing is time-sensitive, so wake
            // every five minutes instead of the default 30 seconds.
            config.flushIntervalSeconds = 5 * 60
            config.getAnonymousId = { _ in distinctID }
            PostHogSDK.shared.setup(config)
            if !isEnabled {
                PostHogSDK.shared.optOut()
            }
            PostHogSDK.shared.register(DeviceInfo.superProperties())
            isBootstrapped = true

            captureLaunchEvents()
        #endif
    }

    static func capture(_ event: AnalyticsEvent) {
        guard isBootstrapped else { return }
        PostHogSDK.shared.capture(event.name, properties: event.properties)
    }

    /// Keeps the provider super properties current so any event can be
    /// sliced by provider mix and plan tier. Called after every refresh;
    /// only re-registers when something changed.
    static func updateProviderContext(activeProviders: [String], planTiers: [String: String]) {
        var context: [String: Any] = [
            "provider_count_active": activeProviders.count,
            "providers_active": activeProviders.sorted(),
        ]
        for (provider, tier) in planTiers {
            context["plan_\(provider)"] = tier
        }
        guard isBootstrapped, !(context as NSDictionary).isEqual(providerContext) else { return }
        providerContext = context as NSDictionary
        PostHogSDK.shared.register(context)
    }

    /// Sends `app_heartbeat` once per calendar day while the app runs.
    /// `usagePressure` is sampled at beat time, not at call time.
    static func startDailyHeartbeat(usagePressure: @escaping @MainActor () -> [String: String]) {
        beatIfNewDay(usagePressure: usagePressure)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                beatIfNewDay(usagePressure: usagePressure)
            }
        }
        // Once a day is the precision that matters; let the system fold
        // this wakeup into others.
        heartbeatTimer?.tolerance = 5 * 60
    }

    private static func beatIfNewDay(usagePressure: @MainActor () -> [String: String]) {
        guard isBootstrapped else { return }
        let today = Date.now.formatted(.iso8601.year().month().day())
        guard UserDefaults.standard.string(forKey: lastHeartbeatDayKey) != today else { return }
        UserDefaults.standard.set(today, forKey: lastHeartbeatDayKey)
        capture(.appHeartbeat(
            uptimeHours: Date.now.timeIntervalSince(launchedAt) / 3600,
            usagePressure: usagePressure()
        ))
    }

    private static func captureLaunchEvents() {
        let version = DeviceInfo.appVersion
        let lastVersion = UserDefaults.standard.string(forKey: lastRunVersionKey)
        if lastVersion == nil {
            capture(.appInstalled)
        }
        capture(.appLaunched)
        if let lastVersion, lastVersion != version {
            capture(.appUpdated(fromVersion: lastVersion, toVersion: version))
        }
        UserDefaults.standard.set(version, forKey: lastRunVersionKey)
    }

    /// The anonymous identity: a random UUID, stored on first use. Not
    /// derived from hardware or anything Apple considers identifying.
    private static func stableDistinctID() -> UUID {
        if let stored = UserDefaults.standard.string(forKey: distinctIDKey),
           let uuid = UUID(uuidString: stored)
        {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: distinctIDKey)
        return uuid
    }
}
