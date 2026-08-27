import Foundation

/// Port of `app/services/offClient.ts`.
///
/// OFF is used only to turn a branded receipt line the offline matcher could not place
/// into a generic product description (its category tags), which is then matched against
/// BLS - so nutrition still comes entirely from BLS. OFF only helps with product IDENTITY.
///
/// Best-effort by design: a short timeout, and ANY failure resolves to nil so the caller
/// silently keeps the BLS-only result. Never throws.
///
/// Data (c) OpenFoodFacts contributors, licensed under the Open Database License (ODbL).
public struct OffProduct {
    /// OFF's product name, shown as the item title when OFF resolved it.
    public let productName: String
    /// Category tags, coarse-to-specific, e.g. ["en:snacks", ..., "en:potato-crisps"].
    public let categoriesTags: [String]
    public let brands: String?
}

public enum OffClient {
    /// Search-a-licious full-text endpoint. The legacy search.pl / v2 search_terms
    /// endpoints are frequently rate-limited; this one is the supported search.
    private static let SEARCH_URL = "https://search.openfoodfacts.org/search"
    /// OFF requires a descriptive User-Agent. Keep it identifying and contactable.
    private static let USER_AGENT = "SmartSwaps/1.0 (Expo receipt scanner; https://github.com/smart-swaps)"

    /// search-a-licious shows two failure modes: fast 502s and multi-second hangs. ONE
    /// retry, not several, and a timeout tight enough that two failed attempts still land
    /// under ~7s total.
    public static let DEFAULT_TIMEOUT_MS = 3000
    /// Gateway/availability codes worth a quick retry - not "no result" (4xx).
    private static let RETRYABLE_STATUSES: Set<Int> = [429, 502, 503, 504]
    private static let MAX_ATTEMPTS = 2
    private static let RETRY_DELAY_MS: UInt64 = 400

    /// Matches `encodeURIComponent`, which escapes more than
    /// `.urlQueryAllowed` does - notably `+`, `&`, `=` and `#`.
    private static let encodeURIComponentAllowed: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-_.!~*'()")
        return s
    }()

    private struct Envelope: Decodable {
        let hits: [Hit]?
        struct Hit: Decodable {
            let product_name: String?
            let categories_tags: [String]?
            let brands: String?
        }
    }

    /// One HTTP attempt. Returns the product, nil for "no result", or throws for a
    /// retryable failure (network error, timeout, or 429/502/503/504).
    private static func attemptLookup(_ q: String, _ session: URLSession,
                                      _ timeoutMs: Int) async throws -> OffProduct? {
        let encoded = q.addingPercentEncoding(withAllowedCharacters: encodeURIComponentAllowed) ?? q
        let urlString = "\(SEARCH_URL)?q=\(encoded)&page_size=1&fields=product_name,categories_tags,brands"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(USER_AGENT, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Double(timeoutMs) / 1000.0

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }

        if !(200...299).contains(http.statusCode) {
            if RETRYABLE_STATUSES.contains(http.statusCode) {
                throw OffError.retryable(http.statusCode)
            }
            return nil  // a definitive non-result (e.g. 400) - retrying won't help
        }

        // Bad JSON throws, and is likewise worth one retry - matching res.json() throwing.
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let hit = envelope.hits?.first else { return nil }

        let productName = hit.product_name ?? ""
        let categoriesTags = hit.categories_tags ?? []
        if productName.isEmpty && categoriesTags.isEmpty { return nil }
        return OffProduct(productName: productName, categoriesTags: categoriesTags, brands: hit.brands)
    }

    enum OffError: Error { case retryable(Int) }

    public static func lookupOffProduct(_ query: String, timeoutMs: Int = DEFAULT_TIMEOUT_MS,
                                        session: URLSession = .shared) async -> OffProduct? {
        let q = EngineStrings.jsTrim(query)
        if q.isEmpty { return nil }

        for attempt in 0..<MAX_ATTEMPTS {
            do {
                return try await attemptLookup(q, session, timeoutMs)
            } catch {
                // Offline, aborted, throttled, gateway error or bad JSON - all transient.
                if attempt == MAX_ATTEMPTS - 1 { return nil }
                try? await Task.sleep(nanoseconds: RETRY_DELAY_MS * 1_000_000)
            }
        }
        return nil
    }
}
