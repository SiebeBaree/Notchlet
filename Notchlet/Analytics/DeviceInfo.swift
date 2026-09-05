import AppKit

/// PostHog super properties. Nothing here identifies the machine: no
/// serial, no hostname, no username.
enum DeviceInfo {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static func superProperties() -> [String: Any] {
        let process = ProcessInfo.processInfo
        let os = process.operatingSystemVersion

        var properties: [String: Any] = [
            "app_version": appVersion,
            "build": build,
            "os_version": "\(os.majorVersion).\(os.minorVersion)"
                + (os.patchVersion > 0 ? ".\(os.patchVersion)" : ""),
            "cpu_cores": process.processorCount,
            "ram_gb": Int(process.physicalMemory / (1 << 30)),
            "arch": arch,
            // With "discard client IP" enabled in PostHog there is no GeoIP;
            // locale and timezone give country-level insight instead.
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
            "display_count": NSScreen.screens.count,
            "has_physical_notch": NSScreen.screens.contains { $0.safeAreaInsets.top > 0 },
        ]
        if let model = sysctlString("hw.model") {
            properties["device_model"] = model
        }
        if let chip = sysctlString("machdep.cpu.brand_string") {
            properties["chip"] = chip
        }
        if let main = NSScreen.main {
            let scale = main.backingScaleFactor
            properties["main_resolution"] = "\(Int(main.frame.width * scale))x\(Int(main.frame.height * scale))"
                + "@\(Int(scale))x"
            properties["main_refresh_hz"] = main.maximumFramesPerSecond
        }
        return properties
    }

    private static var arch: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = Data(count: size)
        let status = buffer.withUnsafeMutableBytes { sysctlbyname(name, $0.baseAddress, &size, nil, 0) }
        guard status == 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}
