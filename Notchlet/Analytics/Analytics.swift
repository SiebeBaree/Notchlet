import Foundation
import PostHog

/// The PostHog SDK (EU cloud). Anonymous: a random UUID is the only
/// identity, `identify()` is never called and person profiles are off.
/// Off entirely in DEBUG builds; every call is a no-op until `bootstrap()`.
enum Analytics {
    /// Substituted into Info.plist from Config/Secrets.xcconfig; empty in a
    /// checkout without that file, which leaves analytics off.
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

    static func bootstrap() {
        #if DEBUG
        #else
            guard !apiKey.isEmpty else { return }

            let distinctID = stableDistinctID()
            let config = PostHogConfig(apiKey: apiKey, host: host)
            config.personProfiles = .never
            config.captureApplicationLifecycleEvents = false
            // The SDK's flush timer fires whether or not anything is
            // queued; events are rare, so every five minutes rather than 30s.
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

    /// Super properties so any event can be sliced by provider mix and
    /// plan tier; re-registered only when something changed.
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

    /// Once per calendar day while the app runs; `usagePressure` is sampled
    /// at beat time.
    static func startDailyHeartbeat(usagePressure: @escaping @MainActor () -> [String: String]) {
        beatIfNewDay(usagePressure: usagePressure)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                beatIfNewDay(usagePressure: usagePressure)
            }
        }
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

    /// A random UUID stored on first use, never derived from hardware.
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
