import Foundation

/// Port of `app/services/overrideStore.ts`.
///
/// Per-user cache of manual corrections: normalized OCR line -> BLS food id. Kept in
/// memory as well as persisted, because the receipt parse loop is synchronous per line:
/// call `load()` once before parsing, then `get()` freely.
///
/// `get()` returns nil until `load()` has completed. That is not a bug to fix - the
/// offline evaluation harness never calls load(), which makes tier 1 inert there, and
/// reproducing the snapshot depends on it.
public final class OverrideStore: @unchecked Sendable {
    public static let shared = OverrideStore()

    private static let OVERRIDES_KEY = "@smart_swaps_overrides"
    private var cache: [String: String]?
    private let lock = NSLock()

    private init() {}

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    /// Safe to call repeatedly; only reads storage once.
    public func load() async {
        if withLock({ cache != nil }) { return }

        let raw = await KeyValueStore.shared.getItem(Self.OVERRIDES_KEY)
        var loaded: [String: String] = [:]
        if let raw, let d = raw.data(using: .utf8),
           let m = try? JSONDecoder().decode([String: String].self, from: d) {
            loaded = m
        }
        withLock { cache = loaded }
    }

    /// Synchronous lookup of a raw OCR line. Returns the BLS food id, or nil.
    public func get(_ rawLine: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let cache = cache else { return nil }
        let key = OverrideKey.normalizeOverrideKey(rawLine)
        if key.isEmpty { return nil }
        return cache[key]
    }

    public func set(_ rawLine: String, _ foodId: String) async {
        let key = OverrideKey.normalizeOverrideKey(rawLine)
        if key.isEmpty { return }  // nothing distinctive left to key on
        await load()
        let next = withLock { () -> [String: String] in
            var n = cache ?? [:]
            n[key] = foodId
            cache = n
            return n
        }
        await persist(next)
    }

    public func remove(_ rawLine: String) async {
        let key = OverrideKey.normalizeOverrideKey(rawLine)
        if key.isEmpty { return }
        await load()
        let next = withLock { () -> [String: String] in
            var n = cache ?? [:]
            n.removeValue(forKey: key)
            cache = n
            return n
        }
        await persist(next)
    }

    public func clear() async {
        withLock { cache = [:] }
        await KeyValueStore.shared.removeItem(Self.OVERRIDES_KEY)
    }

    /// Test seam: drops the in-memory copy so the next load() re-reads storage.
    public func resetForTests() { withLock { cache = nil } }

    private func persist(_ map: [String: String]) async {
        guard let d = try? JSONEncoder().encode(map),
              let s = String(data: d, encoding: .utf8) else { return }
        await KeyValueStore.shared.setItem(Self.OVERRIDES_KEY, s)
    }
}
