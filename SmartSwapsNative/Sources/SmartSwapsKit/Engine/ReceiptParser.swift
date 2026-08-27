import Foundation

/// Port of `app/engine/receiptParser.ts` - German receipt OCR matching.
///
/// The single most fragile file in this port, and the one whose behaviour depends on the
/// most JS-specific details: insertion-ordered Maps decide which candidates get scored,
/// object identity double-counts exact hits, and the final sort uses a comparator that is
/// not a total order. All three are handled explicitly; see PORTING_INVENTORY.md §5.2.
///
/// String lengths and slices operate on Characters. After `normalize`/`asciiFold` the
/// alphabet is ASCII plus precomposed äöüß, where grapheme, scalar and UTF-16 counts all
/// coincide, so this matches JS `.length` exactly for every string that reaches it.
public struct ParsedReceiptItem {
    public var rawText: String
    public var matchedFood: FoodItem?
    public var confidence: Double
    /// 'bls' (default), 'override', 'exact_lookup', 'brand_dict', or 'off'.
    public var source: String?
    /// OpenFoodFacts product name, shown as the title when source == "off".
    public var displayName: String?
    public var quantity: Double?
    public var unit: String?

    public init(rawText: String, matchedFood: FoodItem?, confidence: Double,
                source: String? = nil, displayName: String? = nil,
                quantity: Double? = nil, unit: String? = nil) {
        self.rawText = rawText
        self.matchedFood = matchedFood
        self.confidence = confidence
        self.source = source
        self.displayName = displayName
        self.quantity = quantity
        self.unit = unit
    }
}

public enum ReceiptParser {

    public static func normalize(_ s: String) -> String { EngineStrings.normalize(s) }
    public static func asciiFold(_ s: String) -> String { EngineStrings.asciiFold(s) }

    // MARK: - Regexes, compiled once (as V8 does for module-level literals)

    private static let reFatPct = JSRegex("(\\d+(?:[.,]\\d+)?)\\s*(?:%|fat|fett)", "i")
    private static let reCaseSplit1 = JSRegex("([A-Z]+)([A-Z][a-z])", "g")
    private static let reCaseSplit2 = JSRegex("([a-z])([A-Z])", "g")
    private static let reDigit = JSRegex("\\d", "g")
    private static let rePlainQuantityToken = JSRegex("^\\d+([.,]\\d+)?(g|kg|mg|ml|cl|l|stk|st|er)?$", "i")
    private static let rePreExpandStrip = JSRegex("[^\\w\\säöüßÄÖÜ]", "g")
    private static let reLettersThenDigitThenLetters = JSRegex("^[a-zäöüß]+\\d[a-zäöüß]*$", "i")
    private static let reHasEmbeddedDigit = JSRegex("[a-zäöüß]*\\d[a-zäöüß]+|[a-zäöüß]+\\d[a-zäöüß]*", "i")
    private static let reQuantityNoise = JSRegex("^\\d+([.,]\\d+)?(g|kg|mg|ml|cl|l|stk|st|er)?$", "i")
    private static let reStemSuffix = JSRegex("(en|e|n|s)$")
    private static let reDescriptorStopword = JSRegex("^(sort|sortiert|lose|natur|classic|clas|fein|extra|spezial|surt|frisch|hausgemacht|regional|leicht|light|mix|protein|steinofen|ofenfrisch|pur|marken|pikant|toskana|toscana|provence|griechischer|griechische|beutel|tuete|netz|weiss|wei|weisse)$", "i")
    private static let reParens = JSRegex("\\(([^)]*)\\)", "g")
    private static let reAdditive = JSRegex("\\bE[-\\s]?\\d{3}\\b|additive|chemical|curing salt", "i")

    private static let lookalikes: [Character: Character] = ["0": "o", "1": "l", "5": "s", "6": "g", "8": "b"]

    private static let HEAD_NOUN_SUFFIXES = ["brot", "broetchen", "wurst", "kaese", "milch",
        "saft", "sahne", "creme", "oel", "öl", "schinken", "salat", "suppe", "pudding",
        "paprika", "joghurt", "fleisch", "tee", "wasser", "wein", "bier", "pizza", "reis",
        "baguette", "baguett", "mais", "quark", "nudeln", "butter", "beutel", "tuete",
        "netz", "salami", "koerner", "gemuese"]

    private static let reCoreNoun = JSRegex("joghurt|yogurt|milch|milk|kaese|cheese|brot|bread|pudding|flammkuchen|griess|granatapfel|apfel|apple|banane|banana|tomate|tomato|zwiebel|onion|kartoffel|potato|zitrone|lemon|salami|schinken|ham|wurst|sausage|nuss|nuesse|nut|peanut|erdnuss|reis|rice|fisch|fish|fleisch|meat|eier|egg|birne|pear|traube|grape|gurke|cucumber|mozzarella|gouda|parmesan|ricotta|feta|camembert|edamer|pesto|gnocchi|tortelloni|quark|butter|teigwaren|chili|paprika|skyr|baguette|baguett|roggen|ravioli|salat|pfeffer|pizza|sahne|rahm|creme|haehnchen|hähnchen|huhn|chicken|pute|truthahn|ente|gefluegel|geflügel", "i")

    private static func isCoreNoun(_ t: String) -> Bool { reCoreNoun.test(t) }

    private static let IMPLICIT_QUALIFIERS: Set<String> = ["roh", "raw", "natur", "plain",
        "frisch", "fresh", "min", "mind", "fat", "fett", "dry", "matter", "schwein",
        "rind", "pute", "kalb", "haehnchen", "huhn", "lamm", "pork", "beef", "veal",
        "kochpoekelware", "poekelware", "konserve", "dose", "dosenschinken", "cured",
        "canned", "geroestet", "roasted", "gesalzen", "salted", "getrocknet", "dried"]

    private static let plantBasedKeywords = ["vegan", "soja", "pflanzlich", "vegetarisch", "alternative", "tofu"]
    private static let dietKeywords = ["glutenfrei", "glutenfree", "laktosefrei", "lactosefree", "zuckerfrei", "sugarfree"]
    private static let compositeKeywords = ["gefüllt", "mit", "dessert", "sauce", "aromatisiert"]

    /// Optional out-parameter used by offline evaluation scripts to inspect the ranked
    /// candidate list, not just the winner. Never passed by app code.
    public final class MatchDebug {
        public var ranked: [(food: FoodItem, confidence: Double)] = []
        public init() {}
    }

    public struct MatchResult {
        public let food: FoodItem
        public let confidence: Double
        public let hasStrongHit: Bool
    }

    private static func candidateKeysFor(_ token: [Character],
                                         _ shingleIndex: OrderedDictionary<String, OrderedSet<String>>) -> OrderedSet<String> {
        var keys = OrderedSet<String>()
        if token.count < 5 {
            if let direct = shingleIndex[String(token)] { for k in direct { keys.insert(k) } }
            return keys
        }
        for i in 0...(token.count - 5) {
            if let bucket = shingleIndex[String(token[i..<(i + 5)])] {
                for k in bucket { keys.insert(k) }
            }
        }
        return keys
    }

    private static func candidateKeysFor4Gram(_ token: [Character],
                                              _ fourGramIndex: OrderedDictionary<String, OrderedSet<String>>) -> OrderedSet<String> {
        var keys = OrderedSet<String>()
        if token.count < 4 { return keys }
        for i in 0...(token.count - 4) {
            if let bucket = fourGramIndex[String(token[i..<(i + 4)])] {
                for k in bucket where abs(k.count - token.count) <= 2 { keys.insert(k) }
            }
        }
        return keys
    }

    /// `w.length > 4 ? w.replace(/(en|e|n|s)$/,'') : w`
    @inline(__always)
    private static func dfl(_ w: String) -> String {
        w.count > 4 ? reStemSuffix.replaceFirst(w, "") : w
    }

    public static func matchFoodToOcrText(_ ocrText: String, _ allFoods: [FoodItem],
                                          _ indexData: FoodIndexData? = nil,
                                          _ debug: MatchDebug? = nil) -> MatchResult? {
        var lineFatPct: Double? = nil
        if let m = reFatPct.match(ocrText), let g = m[1] {
            lineFatPct = JSNumber.parseFloat(g.replacingOccurrences(of: ",", with: "."))
        }

        // Apply German abbreviation expansions first.
        var caseSplit = reCaseSplit1.replaceAll(ocrText, "$1 $2")   // "NIPizza" -> "NI Pizza"
        caseSplit = reCaseSplit2.replaceAll(caseSplit, "$1 $2")     // "PizzaSpeciale" -> "Pizza Speciale"

        func replaceDigits(_ w: String) -> String {
            reDigit.replaceAll(w) { groups in
                let d = groups[0] ?? ""
                if let c = d.first, let sub = lookalikes[c] { return String(sub) }
                return d
            }
        }
        // Plain quantity/weight tokens are never a mangled food name - running lookalike
        // substitution on them just manufactures garbage (400g -> 4oog).
        func isPlainQuantityToken(_ w: String) -> Bool { rePlainQuantityToken.test(w) }

        let preExpandStr = rePreExpandStrip.replaceAll(caseSplit, " ")
        let preExpandWords = EngineStrings.splitWhitespace(preExpandStr).filter { !$0.isEmpty }
        var wordsWithVariants: [String] = []

        for w in preExpandWords {
            wordsWithVariants.append(w)
            if isPlainQuantityToken(w) { continue }
            if reLettersThenDigitThenLetters.test(w) {
                wordsWithVariants.append(reDigit.replaceAll(w, ""))
            }
            if reHasEmbeddedDigit.test(w) {
                let v = replaceDigits(w)
                if v != w { wordsWithVariants.append(v) }
            }
        }

        let expandedOcr = GermanAbbreviations.expandGermanAbbreviations(wordsWithVariants.joined(separator: " "))

        var splitHeads = Set<String>()
        let headNounSplit: [String] = EngineStrings.splitWhitespace(expandedOcr).map { word -> String in
            if word.count < 8 { return word }
            let lower = word.lowercased()
            let lowerChars = Array(lower)
            let wordChars = Array(word)
            for suf in HEAD_NOUN_SUFFIXES {
                if lower.hasSuffix(suf) && lower.count > suf.count + 3 {
                    splitHeads.insert(suf)
                    return String(wordChars[0..<(wordChars.count - suf.count)]) + " "
                         + String(wordChars[(wordChars.count - suf.count)...])
                }
                if suf.count >= 4 {
                    let tail = String(lowerChars.suffix(suf.count))
                    if tail.count == suf.count && EngineStrings.levenshtein(tail, suf) <= 1
                        && lower.count > suf.count + 3 {
                        splitHeads.insert(suf)
                        return String(wordChars[0..<(wordChars.count - suf.count)]) + " " + suf
                    }
                    let tailMinus1 = String(lowerChars.suffix(suf.count - 1))
                    if tailMinus1.count == suf.count - 1
                        && EngineStrings.levenshtein(tailMinus1, suf) <= 1
                        && lower.count > suf.count + 2 {
                        splitHeads.insert(suf)
                        return String(wordChars[0..<(wordChars.count - tailMinus1.count)]) + " " + suf
                    }
                    let tailPlus1 = String(lowerChars.suffix(suf.count + 1))
                    if tailPlus1.count == suf.count + 1
                        && EngineStrings.levenshtein(tailPlus1, suf) <= 1
                        && lower.count > suf.count + 4 {
                        splitHeads.insert(suf)
                        return String(wordChars[0..<(wordChars.count - tailPlus1.count)]) + " " + suf
                    }
                }
            }
            return word
        }

        let finalOcr = headNounSplit.joined(separator: " ")
        // Quantity/weight/price tokens never appear in a food's canonical name, so keeping
        // them just dilutes every candidate's confidence equally.
        func isQuantityNoise(_ t: String) -> Bool { reQuantityNoise.test(t) }
        let ocrTokensRaw = EngineStrings.splitWhitespace(normalize(finalOcr))
            .filter { $0.count > 2 && !isQuantityNoise($0) }
        let ocrTokensAscii = EngineStrings.splitWhitespace(asciiFold(finalOcr))
            .filter { $0.count > 2 && !isQuantityNoise($0) }

        if ocrTokensRaw.isEmpty { return nil }

        struct Match { let food: FoodItem; let confidence: Double; let hasStrongHit: Bool; let unmatchedCount: Int }
        var allMatches: [Match] = []

        // Insertion-ordered, and the double insert for an exact hit is the source's own
        // weighting trick - addCand is called twice.
        var candidateHits = OrderedDictionary<FoodItem, Int>(minimumCapacity: 512)
        func addCand(_ f: FoodItem) { candidateHits[f] = (candidateHits[f] ?? 0) + 1 }
        var lineHasRecognizedToken = false

        if let indexData {
            var searchTokens = OrderedSet<String>()
            for t in ocrTokensRaw { searchTokens.insert(t) }
            for t in ocrTokensAscii { searchTokens.insert(t) }

            for token in searchTokens {
                if token.count < 3 { continue }
                let isStop = reDescriptorStopword.test(token)

                let prevHits = candidateHits.count
                let exact = indexData.index[token]
                if let exact {
                    for f in exact { addCand(f); addCand(f) }
                    if !isStop { lineHasRecognizedToken = true }
                }
                let stem = token.count > 4 ? reStemSuffix.replaceFirst(token, "") : token
                if stem != token {
                    if let st = indexData.stemIndex[stem] ?? indexData.stemIndex[token] {
                        for f in st { addCand(f); addCand(f) }
                        if !isStop { lineHasRecognizedToken = true }
                    }
                }

                let tokenChars = Array(token)
                if token.count >= 4 {
                    var found5 = false
                    for key in candidateKeysFor(tokenChars, indexData.shingleIndex) {
                        if key.contains(token) || token.contains(key) || abs(key.count - token.count) <= 2 {
                            for f in indexData.index[key]! { addCand(f) }
                            found5 = true
                        }
                    }
                    if !found5 && token.count >= 5 && token.count <= 8 {
                        for key in candidateKeysFor4Gram(tokenChars, indexData.fourGramIndex) {
                            for f in indexData.index[key]! { addCand(f) }
                        }
                    }
                }

                // Insertion/deletion variants, only if candidateHits did not grow.
                if candidateHits.count == prevHits && exact == nil
                    && token.count >= 5 && token.count <= 10 {
                    var foundVariant = false
                    let CONF: [Character: [Character]] = [
                        "t": ["n", "i", "l"], "i": ["n", "l", "t"], "l": ["i", "t"],
                        "n": ["m", "t", "i", "u", "w"], "m": ["n"], "o": ["0", "e", "u"],
                        "u": ["n", "v", "o"], "v": ["u"], "f": ["t"], "c": ["e", "o"],
                        "e": ["c", "o", "s"], "r": ["n"], "d": ["g", "b"], "g": ["d"],
                        "s": ["e"], "q": ["o"], "w": ["n"], "b": ["d"],
                    ]
                    func tryVariant(_ v: String) {
                        if let hit = indexData.index[v] {
                            for f in hit { addCand(f); addCand(f) }
                            foundVariant = true
                        }
                        let vs = v.count > 4 ? reStemSuffix.replaceFirst(v, "") : v
                        if let hs = indexData.stemIndex[vs] ?? indexData.stemIndex[v] {
                            for f in hs { addCand(f); addCand(f) }
                            foundVariant = true
                        }
                    }
                    for p in 0..<tokenChars.count {
                        guard let alts = CONF[tokenChars[p]] else { continue }
                        for a in alts {
                            var chars = tokenChars
                            chars[p] = a
                            tryVariant(String(chars))
                        }
                    }
                    if !foundVariant {
                        for p in 0..<tokenChars.count {
                            var chars = tokenChars
                            chars.remove(at: p)
                            tryVariant(String(chars))
                        }
                    }
                    if !foundVariant && token.count <= 9 {
                        let a_z = Array("abcdefghijklmnopqrstuvwxyz")
                        for p in 0...tokenChars.count {
                            for charIdx in 0..<26 {
                                var chars = tokenChars
                                chars.insert(a_z[charIdx], at: p)
                                tryVariant(String(chars))
                            }
                        }
                    }
                }
            }
        }

        if !lineHasRecognizedToken || candidateHits.count == 0 { return nil }

        // A common word ("tomaten") hits hundreds of foods, and the hit count is a coarse
        // retrieval prior, not a quality score - so a correct short entry reached only via
        // the stem index could be evicted before it was ever scored. 120 keeps those in play.
        let MAX_CANDIDATES = 120
        var candidatesToScore: [FoodItem]
        if candidateHits.count <= MAX_CANDIDATES {
            candidatesToScore = candidateHits.keys
        } else {
            let sorted = JSSort.sorted(candidateHits.entries) { a, b in
                Double(b.value - a.value)
            }
            candidatesToScore = sorted.prefix(MAX_CANDIDATES).map(\.key)
        }

        for food in candidatesToScore {
            var parenTokens = Set<String>()
            for nm in [food.name, food.name_de].compactMap({ $0 }) where !nm.isEmpty {
                let inParens = reParens.matchAll(nm) ?? []
                for seg in inParens {
                    for t in EngineStrings.splitWhitespace(normalize(seg))
                            + EngineStrings.splitWhitespace(asciiFold(seg)) {
                        if t.count > 2 { parenTokens.insert(t) }
                    }
                }
            }

            struct NameData { let rawStr: String; let asciiStr: String
                              let tokensRaw: [String]; let tokensAscii: [String]; let isFallback: Bool }
            var namesToTest: [NameData] = []

            if let cached = indexData?.cache[food.id] {
                if let de = cached.de {
                    namesToTest.append(NameData(rawStr: de.rawStr, asciiStr: de.asciiStr,
                                                tokensRaw: de.tokensRaw, tokensAscii: de.tokensAscii,
                                                isFallback: false))
                }
                namesToTest.append(NameData(rawStr: cached.en.rawStr, asciiStr: cached.en.asciiStr,
                                            tokensRaw: cached.en.tokensRaw, tokensAscii: cached.en.tokensAscii,
                                            isFallback: true))
            } else {
                if let nameDe = food.name_de, !nameDe.isEmpty {
                    namesToTest.append(NameData(
                        rawStr: normalize(nameDe), asciiStr: asciiFold(nameDe),
                        tokensRaw: EngineStrings.splitWhitespace(normalize(nameDe)).filter { $0.count > 2 },
                        tokensAscii: EngineStrings.splitWhitespace(asciiFold(nameDe)).filter { $0.count > 2 },
                        isFallback: false))
                }
                namesToTest.append(NameData(
                    rawStr: normalize(food.name), asciiStr: asciiFold(food.name),
                    tokensRaw: EngineStrings.splitWhitespace(normalize(food.name)).filter { $0.count > 2 },
                    tokensAscii: EngineStrings.splitWhitespace(asciiFold(food.name)).filter { $0.count > 2 },
                    isFallback: true))
            }

            for nameData in namesToTest {
                let tokenSets: [(ocr: [String], food: [String], fullOcrStr: String, fullFoodStr: String)] = [
                    (ocrTokensRaw, nameData.tokensRaw, ocrTokensRaw.joined(separator: " "), nameData.rawStr),
                    (ocrTokensAscii, nameData.tokensAscii, ocrTokensAscii.joined(separator: " "), nameData.asciiStr),
                ]

                for tSet in tokenSets {
                    if tSet.ocr.isEmpty { continue }

                    var overlapScore = 0.0
                    var totalWeight = 0.0
                    var hasFirstFoodTokenCoreMatch = false
                    var coreNounFound = false

                    for i in 0..<tSet.ocr.count {
                        let oToken = tSet.ocr[i]
                        let isFirstOcrToken = (i == 0)
                        var bestTokenScore = 0.0
                        var bestTokenWasFirstFoodToken = false

                        for j in 0..<tSet.food.count {
                            let nToken = tSet.food[j]
                            let isFirstFoodToken = (j == 0)

                            let minLen = Swift.min(oToken.count, nToken.count)
                            if minLen < 4 && oToken != nToken { continue }

                            let oS = dfl(oToken), nS = dfl(nToken)

                            var simScore = 0.0
                            if oToken == nToken || nToken.hasPrefix(oToken) || oToken.hasPrefix(nToken) {
                                let lenRatio = Double(minLen) / Double(Swift.max(oToken.count, nToken.count))
                                if oToken == nToken {
                                    simScore = 1.0
                                } else if oS == nS {
                                    // Pure German inflection (Tomate/Tomaten): same word, so
                                    // treat as effectively exact. Without this a plural
                                    // receipt line scores higher against an unrelated entry
                                    // that happens to be spelled plural.
                                    simScore = 0.97
                                } else {
                                    simScore = 0.5 + (0.35 * lenRatio)
                                }
                            } else {
                                let dist = EngineStrings.levenshtein(oToken, nToken)
                                let maxLen = Swift.max(oToken.count, nToken.count)
                                var sim = 1 - (Double(dist) / Double(maxLen))
                                let oS2 = dfl(oToken), nS2 = dfl(nToken)
                                if sim > 0.45 && sim <= 0.75 && (oS2 != oToken || nS2 != nToken) {
                                    let sd = 1 - Double(EngineStrings.levenshtein(oS2, nS2))
                                        / Double(Swift.max(oS2.count, nS2.count))
                                    if sd > sim { sim = sd }
                                }
                                if sim > 0.7 {
                                    simScore = sim
                                } else if minLen >= 4 && (nToken.hasPrefix(oToken) || oToken.hasPrefix(nToken)) {
                                    simScore = 0.5 + (0.35 * (Double(minLen) / Double(maxLen)))
                                } else if minLen >= 5 && (nToken.contains(oToken) || oToken.contains(nToken)) {
                                    simScore = 0.4 + (0.35 * (Double(minLen) / Double(maxLen)))
                                } else if minLen >= 4 {
                                    let oChars = Array(oToken)
                                    if oChars.count >= 4 {
                                        for k in 0...(oChars.count - 4) {
                                            let sub = String(oChars[k..<(k + 4)])
                                            if nToken.hasPrefix(sub) || nToken.hasSuffix(sub) {
                                                if oToken.hasPrefix(sub) || oToken.hasSuffix(sub) {
                                                    simScore = Swift.max(simScore, 0.6)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            if simScore > bestTokenScore {
                                bestTokenScore = simScore
                                bestTokenWasFirstFoodToken = isFirstFoodToken
                            }
                        }

                        let isDescriptorStopword = reDescriptorStopword.test(oToken)
                        let isCore = isCoreNoun(oToken) || splitHeads.contains(oToken)

                        // Zero-weight repeated core nouns.
                        var effectiveIsCore = isCore
                        if isCore {
                            if coreNounFound { effectiveIsCore = false }
                            coreNounFound = true
                        }

                        // A repeated core noun shouldn't get the 3x/5x boost again, but an
                        // exact match is still real evidence - fall back to weight 1.
                        var weight: Double = isDescriptorStopword ? 0 : (effectiveIsCore ? 3 : 1)
                        if splitHeads.contains(oToken) && effectiveIsCore { weight = 5 }
                        if isFirstOcrToken && effectiveIsCore { weight *= 1.5 }

                        if bestTokenScore > 0 {
                            if effectiveIsCore && bestTokenWasFirstFoodToken && bestTokenScore > 0.8 {
                                hasFirstFoodTokenCoreMatch = true
                            }
                            overlapScore += bestTokenScore * weight
                        }
                        totalWeight += weight
                    }

                    var confidence = totalWeight > 0 ? overlapScore / totalWeight : 0
                    if hasFirstFoodTokenCoreMatch { confidence += 0.08 }

                    // Food-token coverage, weighted by how central each token is: otherwise
                    // a terse one-word DB name gets an unfair 100%-coverage advantage over
                    // an equally-correct but more descriptive multi-word name.
                    let coverageRelevantFoodTokens = tSet.food.filter {
                        !IMPLICIT_QUALIFIERS.contains($0) && !parenTokens.contains($0)
                    }
                    var matchedFoodTokens = 0
                    var matchedCoverageWeight = 0.0
                    var totalCoverageWeight = 0.0
                    for nToken in coverageRelevantFoodTokens {
                        let tokenWeight: Double = isCoreNoun(nToken) ? 3 : 1
                        totalCoverageWeight += tokenWeight
                        var hasMatch = false
                        for oToken in tSet.ocr {
                            if nToken == oToken { hasMatch = true; break }
                            let dist = EngineStrings.levenshtein(oToken, nToken)
                            let sim = 1 - (Double(dist) / Double(Swift.max(oToken.count, nToken.count)))
                            if sim > 0.6 || (nToken.count >= 4 && (nToken.contains(oToken) || oToken.contains(nToken))) {
                                hasMatch = true; break
                            }
                        }
                        if hasMatch { matchedFoodTokens += 1; matchedCoverageWeight += tokenWeight }
                    }
                    let foodTokenCoverage = totalCoverageWeight > 0
                        ? (matchedCoverageWeight / totalCoverageWeight) : 1
                    confidence = (confidence * 0.65) + (foodTokenCoverage * 0.35)

                    // Full string similarity.
                    let fullDist = EngineStrings.levenshtein(tSet.fullOcrStr, tSet.fullFoodStr)
                    let fullSim = 1 - (Double(fullDist)
                        / Double(Swift.max(tSet.fullOcrStr.count, tSet.fullFoodStr.count)))
                    if fullSim > confidence && fullSim > 0.6 && confidence > 0.1 { confidence = fullSim }

                    // English matches must be much better to beat German native matches.
                    if nameData.isFallback { confidence *= 0.85 }

                    // Category switch penalty: if OCR doesn't mention plant-based terms,
                    // don't fall back to them.
                    let ocrHasPlant = tSet.ocr.contains { t in plantBasedKeywords.contains { t.contains($0) } }
                    let dbHasPlant = tSet.food.contains { t in plantBasedKeywords.contains { t.contains($0) } }
                    if !ocrHasPlant && dbHasPlant { confidence *= 0.6 }

                    // Special-diet descriptors are niche variants; don't prefer them over
                    // the ordinary product unless the receipt says so.
                    let ocrHasDiet = tSet.ocr.contains { t in dietKeywords.contains { t.contains($0) } }
                    let dbHasDiet = tSet.food.contains { t in dietKeywords.contains { t.contains($0) } }
                    if !ocrHasDiet && dbHasDiet { confidence *= 0.7 }

                    // Processed-form mismatch. In a German compound the LAST element says
                    // what the product IS: "...teig" is raw dough, "...eis" is ice cream.
                    // Guards: "teigwaren" is pasta, "...reis" is rice.
                    func isProcessedFormToken(_ t: String) -> Bool {
                        t == "dough"
                            || (t.hasSuffix("teig") && !t.contains("waren"))
                            || (t.count >= 6 && t.hasSuffix("eis") && !t.hasSuffix("reis"))
                    }
                    let ocrHasForm = tSet.ocr.contains(where: isProcessedFormToken)
                    let dbHasForm = tSet.food.contains(where: isProcessedFormToken)
                    if dbHasForm && !ocrHasForm { confidence *= 0.65 }

                    // Composite dish penalty: prefer plain base nouns over filled dishes.
                    let dbIsComposite = tSet.food.contains { t in compositeKeywords.contains { t.contains($0) } }
                    if dbIsComposite { confidence *= 0.8 }

                    // Implausible categories. Checks the food's own NAME only - broad
                    // category buckets also contain ordinary spices and condiments, and
                    // checking the category text deprioritized all of them.
                    let isAdditive = reAdditive.test(food.name)
                    if isAdditive && confidence < 0.95 { confidence *= 0.4 }

                    // Additive bonus (NOT a hard floor) so relative ranking among core-noun
                    // matches is preserved rather than collapsing to identical scores.
                    var coreNounFloor = 0.0
                    for oToken in tSet.ocr {
                        for nToken in tSet.food {
                            if !isCoreNoun(nToken) && !isCoreNoun(oToken) { continue }
                            if oToken == nToken { coreNounFloor = Swift.max(coreNounFloor, 0.55); continue }
                            let oS2 = oToken.count > 4 ? reStemSuffix.replaceFirst(oToken, "") : oToken
                            let nS2 = nToken.count > 4 ? reStemSuffix.replaceFirst(nToken, "") : nToken
                            let d = EngineStrings.levenshtein(oS2, nS2)
                            let s = 1 - Double(d) / Double(Swift.max(oS2.count, nS2.count))
                            if s > 0.75 { coreNounFloor = Swift.max(coreNounFloor, 0.5) }
                        }
                    }
                    confidence = Swift.min(0.95, confidence + coreNounFloor * 0.2)

                    // Fat-percentage tie-break, applied LAST (after the cap) so it always
                    // separates two otherwise-identical candidates instead of the cap
                    // saturating both to the same score first.
                    if let lineFatPct {
                        let foodNameStr = nameData.isFallback
                            ? food.name
                            : (food.name_de.flatMap { $0.isEmpty ? nil : $0 } ?? food.name)
                        if let fm = reFatPct.match(foodNameStr), let g = fm[1] {
                            let foodFatPct = JSNumber.parseFloat(g.replacingOccurrences(of: ",", with: "."))
                            confidence -= abs(lineFatPct - foodFatPct) * 0.01
                        } else {
                            confidence -= 0.05
                        }
                    }

                    let unmatchedCount = coverageRelevantFoodTokens.count - matchedFoodTokens

                    var candidateStrongHit = false
                    for oToken in tSet.ocr {
                        for nToken in tSet.food {
                            if oToken == nToken || dfl(oToken) == dfl(nToken) { candidateStrongHit = true }
                        }
                    }

                    allMatches.append(Match(food: food, confidence: confidence,
                                            hasStrongHit: candidateStrongHit,
                                            unmatchedCount: unmatchedCount))
                }
            }
        }

        if allMatches.isEmpty { return nil }

        // NOT a total order - see JSSort.
        let sorted = JSSort.sorted(allMatches) { a, b in
            if abs(b.confidence - a.confidence) <= 0.03 {
                return Double(a.unmatchedCount - b.unmatchedCount)
            }
            return b.confidence - a.confidence
        }

        let bestMatch = sorted[0]
        debug?.ranked = sorted.map { (food: $0.food, confidence: $0.confidence) }

        // Matches are returned even at low confidence so the UI can flag them.
        return MatchResult(food: bestMatch.food, confidence: bestMatch.confidence,
                           hasStrongHit: lineHasRecognizedToken)
    }

    // MARK: - Line classification

    private static func asciiLow(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
    }

    private static let META_TOKENS: Set<String> = [
        "pfand", "leergut", "summe", "total", "mwst", "steuer", "rabatt", "coupon",
        "aktions", "gutschein", "rueckgeld", "visa", "mastercard", "maestro",
        "girocard", "ec-karte", "gegeben", "rueck", "kasse", "bediener", "nr",
        "datum", "uhrzeit", "artikel", "netto", "brutto", "eur", "euro",
        "kartenzahlung", "barzahlung", "zahlen", "kreditkarte", "kontaktlos",
        "kundenbeleg", "kunden", "beleg", "geg", "bezahlung", "contactless",
    ]
    private static let UNIT: Set<String> = ["st", "stk", "pck", "pkg", "btl", "lose", "vke", "sort", "ca", "ab", "pk"]
    private static let legalEntities: Set<String> = ["ohg", "ohb", "gmbh", "inhaber", "ust", "uid"]
    private static let storeNames: Set<String> = ["rewe", "aldi", "lidl", "edeka", "kaufland", "netto", "penny"]
    private static let addrWords: Set<String> = ["allee", "strasse", "straße", "platz", "weg", "gasse", "damm", "ring", "ufer"]

    private static let reStreet = JSRegex("[a-z]+strasse(\\s+\\d+)?$")
    private static let reWord3 = JSRegex("[a-z]{3,}")
    private static let rePriceAny = JSRegex("\\d[.,]\\d{2}")
    private static let reBareNumber = JSRegex("^-?\\d+([.,]\\d+)?\\s*(kgx|kg|g|x)?$")
    private static let reMultiply = JSRegex("^\\d+\\s*x\\s*-?\\d+[.,]\\d{2}", "i")
    private static let reEurPerKg = JSRegex("\\beur\\s*/\\s*kg\\b", "i")
    private static let reWeightLead = JSRegex("^\\d+[.,]\\d+\\s*(kg|g)\\b", "i")
    private static let rePriceTax = JSRegex("^-?\\d+[.,]\\d{2}\\s*[a-c]?$", "i")
    private static let reWeb = JSRegex("www|http|\\.de\\b|\\.com\\b|online", "i")
    private static let reStrasseUml = JSRegex("[a-zäöü]+stra(ß|ss)e$", "i")
    private static let reStkOnly = JSRegex("^\\d+\\s*stk\\.?\\s*x?$", "i")
    private static let reNonWordToSpace = JSRegex("[^\\w\\s]", "g")
    private static let reNumberPattern = JSRegex("\\d+(-\\d+)?")
    private static let rePriceSuffix = JSRegex("[a-c]$", "i")
    private static let rePostcode = JSRegex("^\\d{4,5}\\b")
    private static let reOnlyLetters = JSRegex("^[a-z]+$")
    private static let reNonLetters = JSRegex("[^a-z]", "g")
    private static let reHyphen = JSRegex("-", "g")

    public static func isLikelyProductLine(_ line: String) -> Bool {
        let low = line.lowercased()
        let asciiLowStr = asciiLow(line)

        // Reject street names ("Müllerstraße 141").
        if reStreet.test(asciiLowStr) { return false }

        // Ignore UI text if the user scans a screenshot of the app's own results screen.
        if low.hasPrefix("swap: ") || low.hasPrefix("scanned: ") || low.contains("b swap:") { return false }

        let tokens1 = EngineStrings.splitWhitespace(asciiLowStr)
        let wordTokens1 = tokens1.filter { reWord3.test($0) && !UNIT.contains($0) }
        if wordTokens1.isEmpty { return false }

        // Reject legal-entity / person-name headers.
        if wordTokens1.contains(where: { legalEntities.contains($0) }) { return false }

        let hasPrice1 = rePriceAny.test(low)

        if line.count < 4 { return false }
        if reBareNumber.test(low) { return false }
        if reMultiply.test(low) { return false }
        if reEurPerKg.test(low) { return false }
        if reWeightLead.test(low) { return false }
        if rePriceTax.test(low) { return false }
        if reWeb.test(low) { return false }
        if reStrasseUml.test(low) { return false }
        if reStkOnly.test(low) { return false }

        let tokens2 = EngineStrings.splitWhitespace(reNonWordToSpace.replaceAll(low, " ")).filter { !$0.isEmpty }
        if tokens2.contains(where: { META_TOKENS.contains($0) }) { return false }

        if !tokens2.isEmpty && storeNames.contains(tokens2[0]) { return false }

        let hasAddrWord = tokens2.contains { addrWords.contains($0) }
        let hasNumberPattern = reNumberPattern.test(low)
        let hasPriceSuffix = rePriceSuffix.test(low)
        let hasPriceForAddr = rePriceAny.test(low)
        if hasAddrWord && hasNumberPattern && !hasPriceForAddr && !hasPriceSuffix { return false }

        // Reject postal-code + place-name lines ("10247 Berlin", "13353 Berlin."):
        // a leading 4-5 digit number followed only by plain word tokens, no price.
        if rePostcode.test(asciiLowStr) && !hasPrice1 {
            let restTokens = tokens1.dropFirst().map { reNonLetters.replaceAll($0, "") }.filter { !$0.isEmpty }
            if !restTokens.isEmpty && restTokens.allSatisfy({ reOnlyLetters.test($0) }) { return false }
        }

        if (reHyphen.matchAll(line)?.count ?? 0) >= 3 && !rePriceAny.test(line) { return false }

        let wordTokens2 = tokens2.filter { reWord3.test($0) && !UNIT.contains($0) }
        if wordTokens2.isEmpty { return false }
        let hasPrice2 = rePriceAny.test(low)
        if !hasPrice2 && wordTokens2.count < 2 && !wordTokens2.contains(where: { $0.count >= 4 }) { return false }
        return true
    }

    public static func parseReceiptLine(_ line: String, _ allFoods: [FoodItem],
                                        _ indexData: FoodIndexData? = nil) -> ParsedReceiptItem? {
        if !isLikelyProductLine(line) { return nil }

        let match = matchFoodToOcrText(line, allFoods, indexData)

        if match == nil || !(match!.hasStrongHit) {
            let wordTokens = EngineStrings.splitWhitespace(asciiLow(line)).filter { reWord3.test($0) }
            if wordTokens.isEmpty { return nil }
        }

        return ParsedReceiptItem(rawText: line,
                                 matchedFood: match?.food,
                                 confidence: match?.confidence ?? 0)
    }

    public static func parseReceipt(_ ocrLines: [String], _ allFoods: [FoodItem],
                                    _ indexData: FoodIndexData? = nil) -> [ParsedReceiptItem] {
        var results: [ParsedReceiptItem] = []
        for line in ocrLines {
            if let parsed = parseReceiptLine(line, allFoods, indexData) { results.append(parsed) }
        }
        return results
    }
}
