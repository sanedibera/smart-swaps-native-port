import Foundation

/// The AsyncStorage replacement.
///
/// AsyncStorage on iOS is a plain key -> string store, so this is too. Keys are kept
/// byte-identical to the RN app's (`@smart_swaps_profile`, `swap_training_log_v1`, ...),
/// and values stay JSON strings, which means a value written by either app is readable by
/// the other - useful for the Phase 7 side-by-side.
///
/// Large collections (`@smart_swaps_scans`) go to a JSON file rather than UserDefaults,
/// which is not meant for payloads of that size.
public actor KeyValueStore {
    public static let shared = KeyValueStore()

    /// Keys whose values can grow past a few KB and therefore live on disk.
    private static let fileBacked: Set<String> = [
        "@smart_swaps_scans", "swap_training_log_v1", "match_diagnostic_log_v1",
        "@smart_swaps_overrides",
    ]

    private let defaults = UserDefaults.standard
    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        directory = base.appendingPathComponent("SmartSwapsStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(_ key: String) -> URL {
        // Key names contain '@', which is legal in a filename but noisy; hash-free
        // escaping keeps the files greppable during the side-by-side comparison.
        let safe = key.replacingOccurrences(of: "@", with: "at_")
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }

    public func getItem(_ key: String) -> String? {
        if Self.fileBacked.contains(key) {
            return try? String(contentsOf: fileURL(key), encoding: .utf8)
        }
        return defaults.string(forKey: key)
    }

    public func setItem(_ key: String, _ value: String) {
        if Self.fileBacked.contains(key) {
            try? value.write(to: fileURL(key), atomically: true, encoding: .utf8)
        } else {
            defaults.set(value, forKey: key)
        }
    }

    public func removeItem(_ key: String) {
        if Self.fileBacked.contains(key) {
            try? FileManager.default.removeItem(at: fileURL(key))
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
