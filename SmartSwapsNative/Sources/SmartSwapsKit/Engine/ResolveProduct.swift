import Foundation

/// Port of `app/engine/resolveProduct.ts`.
///
/// A line is resolved through a fixed priority of sources:
///   1. override     - the user's saved manual corrections (offline, authoritative)
///   2. exact_lookup - pre-seeded verified exact-string dictionary
///   3. brand_dict   - pre-seeded verified brand/bare-noun dictionary
///   4. bls-direct   - the offline fuzzy matcher
///   5. off          - OpenFoodFacts, on demand, gated behind a default-off setting
///
/// Nutrition ALWAYS comes from BLS: OFF only turns a branded line into a generic product
/// description, which is then matched against BLS.
public enum ResolveProduct {

    /// Below this confidence a BLS-direct result is "weak" and worth an OFF lookup.
    public static let OFF_UPGRADE_THRESHOLD = 0.45
    /// A BLS match derived from an OFF category must clear this to replace the weak result.
    public static let OFF_BRIDGE_MIN_CONFIDENCE = 0.6
    /// A known-correct answer for that literal string.
    public static let EXACT_LOOKUP_CONFIDENCE = 0.99
    /// Pre-verified, but not as authoritative as a user override.
    public static let BRAND_DICT_CONFIDENCE = 0.95

    public struct Deps {
        public let allFoods: [FoodItem]
        public let foodIndexData: FoodIndexData?
        public init(allFoods: [FoodItem], foodIndexData: FoodIndexData?) {
            self.allFoods = allFoods
            self.foodIndexData = foodIndexData
        }
    }

    /// A brand_dict value ending in " roh" is the generic raw form of a common ingredient
    /// (851 of the 978 entries). Those exist to catch compounds bls-direct cannot split
    /// ("Strauchtomaten"), but a bare key can ALSO win as a whole-word substring inside a
    /// longer, more specific name that bls-direct would have resolved correctly on its own
    /// ("Tomaten ganz, geschält" is canned, not raw). So only accept a "roh"-shaped hit if
    /// bls-direct has nothing confident to say. The threshold matches ReceiptItemList's
    /// own "confident" cutoff rather than inventing a new number.
    private static let GENERIC_BRAND_ENTRY_DEFER_THRESHOLD = 0.72
    private static let reGenericRaw = JSRegex(" roh$")
    private static func isGenericRawEntry(_ value: String) -> Bool { reGenericRaw.test(value) }

    /// Tiers 1-4. Returns nil only when the line is receipt noise the matcher rejects.
    public static func resolveProductLine(_ line: String, _ deps: Deps) -> ParsedReceiptItem? {
        // Tier 1: a saved correction wins outright. Returns nil until load() has completed.
        if let overrideId = OverrideStore.shared.get(line) {
            if let food = deps.allFoods.first(where: { $0.id == overrideId }) {
                return ParsedReceiptItem(rawText: line, matchedFood: food,
                                         confidence: 1.0, source: "override")
            }
            // Override points at a food that no longer exists; fall through to matching.
        }

        var result: ParsedReceiptItem? = nil

        // Tier 2: pre-seeded verified exact-string dictionary.
        if let exactName = ExactLookup.matchExactLookup(line) {
            if let food = deps.allFoods.first(where: { $0.name_de == exactName || $0.name == exactName }) {
                result = ParsedReceiptItem(rawText: line, matchedFood: food,
                                           confidence: EXACT_LOOKUP_CONFIDENCE,
                                           source: "exact_lookup")
            }
        }

        // Tier 3: pre-seeded verified brand/bare-noun dictionary.
        if result == nil, let brandName = BrandDict.matchBrandDict(line) {
            if let food = deps.allFoods.first(where: { $0.name_de == brandName || $0.name == brandName }) {
                if isGenericRawEntry(brandName) {
                    let direct = ReceiptParser.parseReceiptLine(line, deps.allFoods, deps.foodIndexData)
                    if let direct, direct.matchedFood != nil,
                       direct.confidence >= GENERIC_BRAND_ENTRY_DEFER_THRESHOLD {
                        var r = direct; r.source = "bls"; result = r
                    } else {
                        result = ParsedReceiptItem(rawText: line, matchedFood: food,
                                                   confidence: BRAND_DICT_CONFIDENCE,
                                                   source: "brand_dict")
                    }
                } else {
                    result = ParsedReceiptItem(rawText: line, matchedFood: food,
                                               confidence: BRAND_DICT_CONFIDENCE,
                                               source: "brand_dict")
                }
            }
        }

        // Tier 4: the offline BLS matcher.
        if result == nil {
            if let direct = ReceiptParser.parseReceiptLine(line, deps.allFoods, deps.foodIndexData) {
                var r = direct; r.source = "bls"; result = r
            }
        }

        guard let result else { return nil }  // genuine receipt noise

        // Safety gate: a query known to make every automated tier confidently wrong is
        // forced back to "not found" - a confident wrong nutrition match is worse than an
        // honest miss. Never applies to tier 1.
        if KnownNonMatches.isKnownNonMatch(line) {
            return ParsedReceiptItem(rawText: line, matchedFood: nil, confidence: 0)
        }
        return result
    }

    private static let reLangPrefix = JSRegex("^[a-z]{2}:")
    private static let reDashUnderscore = JSRegex("[-_]", "g")
    private static func cleanCategoryTag(_ tag: String) -> String {
        EngineStrings.jsTrim(reDashUnderscore.replaceAll(reLangPrefix.replaceFirst(tag, ""), " "))
    }

    /// OFF leaf food-type categories are short noun phrases. Long descriptive tags
    /// ("salty snacks made from potato") are not food names and fuzzy-match unrelated BLS
    /// entries (that one lands on potato dumplings), so tags longer than this are ignored.
    private static let MAX_TAG_WORDS = 3

    /// Bridge an OFF product onto a BLS food. Returns nil when nothing maps cleanly,
    /// leaving the line unresolved rather than forcing a wrong nutrition row.
    public static func bridgeOffToBls(_ off: OffProduct, _ deps: Deps) -> ParsedReceiptItem? {
        let enTags = off.categoriesTags.filter { $0.hasPrefix("en:") }
        var best: (food: FoodItem, confidence: Double)? = nil

        for tag in enTags {
            let text = cleanCategoryTag(tag)
            if text.count < 3 { continue }
            if EngineStrings.splitWhitespace(text).count > MAX_TAG_WORDS { continue }
            guard let m = ReceiptParser.parseReceiptLine(text, deps.allFoods, deps.foodIndexData),
                  let food = m.matchedFood, m.confidence >= OFF_BRIDGE_MIN_CONFIDENCE else { continue }
            if best == nil || m.confidence > best!.confidence {
                best = (food, m.confidence)
            }
        }

        guard let best else { return nil }
        return ParsedReceiptItem(
            rawText: "",   // filled in by the caller with the original OCR line
            matchedFood: best.food, confidence: best.confidence,
            source: "off",
            displayName: off.productName.isEmpty ? nil : off.productName)
    }

    /// Second pass over the lines the offline path left weak. Best-effort and fully
    /// optional: offline or on any OFF failure the items come back unchanged. A saved
    /// override is never overridden by OFF.
    ///
    /// `enabled` is required, not defaulted, so every call site makes an explicit
    /// decision. When false this makes ZERO network calls.
    public static func enrichWithOff(
        _ items: [ParsedReceiptItem], _ deps: Deps, _ enabled: Bool,
        lookup: ((String) async -> OffProduct?)? = nil
    ) async -> [ParsedReceiptItem] {
        if !enabled { return items }
        let doLookup = lookup ?? { await OffClient.lookupOffProduct($0) }
        var result = items

        for i in result.indices {
            let item = result[i]
            if item.source == "override" { continue }
            let weak = item.matchedFood == nil || item.confidence < OFF_UPGRADE_THRESHOLD
            if !weak { continue }

            // Query OFF with the product words only - sizes and prices in the raw line
            // ("Nutella 400g") otherwise pollute the search and return the wrong product.
            let query = OverrideKey.normalizeOverrideKey(item.rawText)
            if query.isEmpty { continue }

            guard let off = await doLookup(query) else { continue }
            if var bridged = bridgeOffToBls(off, deps) {
                bridged.rawText = item.rawText
                result[i] = bridged
            }
        }
        return result
    }
}
