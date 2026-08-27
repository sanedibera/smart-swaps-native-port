import Foundation

/// Port of `app/engine/overrideKey.ts`.
///
/// Strips enough that "Zeus Feta 200g" and "Zeus Feta 400g" share a key, but not so much
/// that different products collapse onto one - only quantities, prices, units and the
/// trailing tax letter are removed, never words.
public enum OverrideKey {
    private static let rePrice = JSRegex("\\b\\d+[.,]\\d{2}\\b", "g")
    private static let reWeight = JSRegex("\\b\\d+([.,]\\d+)?\\s*(mg|kg|g|ml|cl|l)\\b", "g")
    private static let reCount = JSRegex("\\b\\d+\\s*(x|st|stk|er)\\b", "g")
    private static let reTaxLetter = JSRegex("\\s+[a-c]\\s*$")
    private static let rePunct = JSRegex("[^\\p{L}\\p{N}]+", "gu")
    private static let reSpaces = JSRegex("\\s+", "g")

    /// Returns "" when nothing usable is left; callers must not store an empty key.
    public static func normalizeOverrideKey(_ rawLine: String) -> String {
        var s = rawLine.lowercased()
        s = rePrice.replaceAll(s, " ")
        s = reWeight.replaceAll(s, " ")
        s = reCount.replaceAll(s, " ")
        s = reTaxLetter.replaceFirst(s, " ")
        // Punctuation to spaces, deliberately AFTER the numeric passes so "3,5" is still
        // intact above and only splits into "3 5" here.
        s = rePunct.replaceAll(s, " ")
        return EngineStrings.jsTrim(reSpaces.replaceAll(s, " "))
    }
}

/// Port of `app/engine/exactLookup.ts` - 332 verified exact-string entries.
public enum ExactLookup {
    private static let map: [String: String] = {
        let pairs = try! OrderedJSON.stringPairs(from: Resources.data("exactLookup.json"))
        return Dictionary(pairs, uniquingKeysWith: { _, b in b })
    }()
    public static func matchExactLookup(_ rawLine: String) -> String? {
        map[EngineStrings.jsTrim(rawLine).lowercased()]
    }
}

/// Port of `app/engine/knownNonMatches.ts`.
///
/// Specific OCR strings where every automated tier's confident answer is known to be
/// wrong, and sometimes actively misleading ("Bacon vegan" resolving to literal pork).
public enum KnownNonMatches {
    private static let keys: Set<String> = {
        let pairs = try! OrderedJSON.stringPairs(from: Resources.data("knownNonMatches.json"))
        return Set(pairs.map(\.0))
    }()
    public static func isKnownNonMatch(_ rawLine: String) -> Bool {
        keys.contains(EngineStrings.jsTrim(rawLine).lowercased())
    }
}

/// Port of `app/engine/brandDict.ts` - 978 verified brand/bare-noun entries.
public enum BrandDict {
    /// Keys sorted longest-first. JS's sort is STABLE, so equal-length keys stay in JSON
    /// insertion order, and that order decides which of two equally long entries wins -
    /// which is why the file is read with an order-preserving parser rather than decoded
    /// into a Dictionary.
    private static let state: (keys: [String], map: [String: String]) = {
        let pairs = try! OrderedJSON.stringPairs(from: Resources.data("verifiedBrandMap.json"))
        let map = Dictionary(pairs, uniquingKeysWith: { a, _ in a })
        let sorted = JSSort.sorted(pairs.map(\.0)) { a, b in
            Double(b.utf16.count - a.utf16.count)
        }
        return (sorted, map)
    }()

    private static let reGermanLetter = JSRegex("[a-zäöüß]", "i")
    private static func isGermanLetter(_ c: Character) -> Bool {
        reGermanLetter.test(String(c))
    }

    /// In a German compound the LAST element says what the product actually IS, and these
    /// heads denote a different product from the bare ingredient a key names - "Apfelmus"
    /// is not "Apfel". Deliberately narrow: a general word-boundary requirement was tried
    /// and reverted, because compounds routinely embed a key legitimately as the SAME
    /// product ("Rispentomaten" is still a tomato).
    private static let PROCESSED_FORM_SUFFIXES = ["mus", "mark", "saft", "öl", "oel", "creme", "brei"]

    private static func isProcessedFormMatch(_ line: [Character], _ keyCount: Int, _ idx: Int) -> Bool {
        var wordEnd = idx + keyCount
        while wordEnd < line.count && isGermanLetter(line[wordEnd]) { wordEnd += 1 }
        let remainder = String(line[(idx + keyCount)..<wordEnd])
        return PROCESSED_FORM_SUFFIXES.contains { remainder.hasSuffix($0) }
    }

    /// Scans every occurrence of `key`, skipping ones blocked by the processed-form guard,
    /// and reports whether any is a COMPLETE WHOLE WORD.
    private static func findOccurrence(_ line: [Character], _ key: [Character]) -> Bool? {
        var from = 0
        var sawEmbedded = false
        while true {
            guard let idx = indexOf(line, key, from) else { break }
            if !isProcessedFormMatch(line, key.count, idx) {
                let before: Character? = idx > 0 ? line[idx - 1] : nil
                let after: Character? = idx + key.count < line.count ? line[idx + key.count] : nil
                let beforeIsLetter = before.map(isGermanLetter) ?? false
                let afterIsLetter = after.map(isGermanLetter) ?? false
                if !beforeIsLetter && !afterIsLetter { return true }
                sawEmbedded = true
            }
            from = idx + 1
        }
        return sawEmbedded ? false : nil
    }

    private static func indexOf(_ haystack: [Character], _ needle: [Character], _ from: Int) -> Int? {
        if needle.isEmpty { return from <= haystack.count ? from : nil }
        if needle.count > haystack.count { return nil }
        var i = Swift.max(0, from)
        while i + needle.count <= haystack.count {
            var j = 0
            while j < needle.count && haystack[i + j] == needle[j] { j += 1 }
            if j == needle.count { return i }
            i += 1
        }
        return nil
    }

    /// A key matching as a complete whole word always wins over one that only matches
    /// embedded, regardless of length - in "Minipflaumen Tomaten", standalone "tomaten"
    /// must beat "pflaumen" appearing inside "minipflaumen" despite being a letter longer.
    public static func matchBrandDict(_ rawLine: String) -> String? {
        let line = Array(EngineStrings.jsTrim(rawLine).lowercased())
        var firstEmbeddedKey: String? = nil
        for key in state.keys {
            guard let wholeWord = findOccurrence(line, Array(key)) else { continue }
            if wholeWord { return state.map[key] }
            if firstEmbeddedKey == nil { firstEmbeddedKey = key }
        }
        return firstEmbeddedKey.flatMap { state.map[$0] }
    }
}
