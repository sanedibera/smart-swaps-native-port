import Foundation

/// Port of `app/engine/foodIndex.ts`.
///
/// Every map here is INSERTION-ORDERED. That is not cosmetic: `matchFoodToOcrText`
/// iterates `index.get(token)` sets to populate `candidateHits`, whose own iteration order
/// then decides which 120 candidates get scored when the pool is larger than the cap.
public struct FoodTokensCache {
    public let rawStr: String
    public let asciiStr: String
    public let tokensRaw: [String]
    public let tokensAscii: [String]
}

public struct FoodIndexData {
    public var index: OrderedDictionary<String, OrderedSet<FoodItem>>
    public var cache: [String: (de: FoodTokensCache?, en: FoodTokensCache)]
    public var shingleIndex: OrderedDictionary<String, OrderedSet<String>>
    public var fourGramIndex: OrderedDictionary<String, OrderedSet<String>>
    public var stemIndex: OrderedDictionary<String, OrderedSet<FoodItem>>
}

public enum FoodIndex {

    static let DB_HEAD_NOUN_SUFFIXES = ["brot", "broetchen", "wurst", "kaese", "milch",
        "saft", "sahne", "creme", "oel", "öl", "schinken", "salat", "suppe", "pudding",
        "paprika", "joghurt", "fleisch", "tee", "wasser", "wein", "bier", "pizza", "reis",
        "baguette", "baguett", "mais", "quark", "nudeln", "butter", "beutel", "tuete",
        "netz", "salami", "koerner", "gemuese"]

    private static let reStemSuffix = JSRegex("(en|e|n|s)$")

    static func withHeadNounSplits(_ tokens: [String]) -> [String] {
        var out = tokens
        for t in tokens {
            if t.count < 8 { continue }
            for suf in DB_HEAD_NOUN_SUFFIXES {
                if t.hasSuffix(suf) && t.count > suf.count + 3 {
                    out.append(String(t.dropLast(suf.count)))
                    out.append(suf)
                    break
                }
            }
        }
        return out
    }

    public static func buildFoodIndex(_ foodsData: [FoodItem]) -> FoodIndexData {
        var index = OrderedDictionary<String, OrderedSet<FoodItem>>(minimumCapacity: 8192)
        var cache = [String: (de: FoodTokensCache?, en: FoodTokensCache)](minimumCapacity: foodsData.count)
        var stemIndex = OrderedDictionary<String, OrderedSet<FoodItem>>(minimumCapacity: 4096)

        for food in foodsData {
            let enRaw = EngineStrings.normalize(food.name)
            let enAscii = EngineStrings.asciiFold(food.name)
            let en = FoodTokensCache(
                rawStr: enRaw,
                asciiStr: enAscii,
                tokensRaw: withHeadNounSplits(EngineStrings.splitWhitespace(enRaw).filter { $0.count > 2 }),
                tokensAscii: withHeadNounSplits(EngineStrings.splitWhitespace(enAscii).filter { $0.count > 2 })
            )
            var de: FoodTokensCache? = nil
            if let nameDe = food.name_de, !nameDe.isEmpty {
                let deRaw = EngineStrings.normalize(nameDe)
                let deAscii = EngineStrings.asciiFold(nameDe)
                de = FoodTokensCache(
                    rawStr: deRaw,
                    asciiStr: deAscii,
                    tokensRaw: withHeadNounSplits(EngineStrings.splitWhitespace(deRaw).filter { $0.count > 2 }),
                    tokensAscii: withHeadNounSplits(EngineStrings.splitWhitespace(deAscii).filter { $0.count > 2 })
                )
            }
            cache[food.id] = (de: de, en: en)

            // JS builds a Set from de.tokensRaw, de.tokensAscii, en.tokensRaw,
            // en.tokensAscii in that order; insertion order is what the index keys inherit.
            var allTokens = OrderedSet<String>()
            if let de {
                for t in de.tokensRaw { allTokens.insert(t) }
                for t in de.tokensAscii { allTokens.insert(t) }
            }
            for t in en.tokensRaw { allTokens.insert(t) }
            for t in en.tokensAscii { allTokens.insert(t) }

            for token in allTokens {
                var set = index[token] ?? OrderedSet<FoodItem>()
                set.insert(food)
                index[token] = set
            }

            for t in allTokens where t.count > 4 {
                let s = reStemSuffix.replaceFirst(t, "")
                if s.count > 2 && s != t {
                    var set = stemIndex[s] ?? OrderedSet<FoodItem>()
                    set.insert(food)
                    stemIndex[s] = set
                }
            }
        }

        let SHINGLE_LEN = 5
        var shingleIndex = OrderedDictionary<String, OrderedSet<String>>(minimumCapacity: 16384)
        for key in index.keys {
            let u = Array(key.utf16)
            if u.count < SHINGLE_LEN {
                var set = shingleIndex[key] ?? OrderedSet<String>()
                set.insert(key)
                shingleIndex[key] = set
                continue
            }
            for i in 0...(u.count - SHINGLE_LEN) {
                let sh = String(decoding: u[i..<(i + SHINGLE_LEN)], as: UTF16.self)
                var set = shingleIndex[sh] ?? OrderedSet<String>()
                set.insert(key)
                shingleIndex[sh] = set
            }
        }

        var fourGramIndex = OrderedDictionary<String, OrderedSet<String>>(minimumCapacity: 8192)
        for key in index.keys {
            let u = Array(key.utf16)
            if u.count < 4 || u.count > 10 { continue }
            for i in 0...(u.count - 4) {
                let g = String(decoding: u[i..<(i + 4)], as: UTF16.self)
                var set = fourGramIndex[g] ?? OrderedSet<String>()
                set.insert(key)
                fourGramIndex[g] = set
            }
        }

        return FoodIndexData(index: index, cache: cache, shingleIndex: shingleIndex,
                             fourGramIndex: fourGramIndex, stemIndex: stemIndex)
    }
}
