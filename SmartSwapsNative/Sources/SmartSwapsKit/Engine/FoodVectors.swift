import Foundation

/// Port of `app/engine/foodVectors.ts` (82 ln) - a hashed bag-of-words cosine similarity,
/// NOT a semantic embedding (see the source's own "HONEST SCOPE" note). PORTING_INVENTORY.md
/// §5.1 called this file "dead - nothing imports it", but the working tree read for Phase 5
/// has `recipeSwapAlgorithm.ts` (also not deleted, contrary to that same inventory entry)
/// calling `computeVectorSimilarity` directly - the inventory was evidently written against
/// a different tree state than what's actually in this repo. Trusting the current source
/// over the stale summary, per the brief's own rule 1.
public enum FoodVectors {
    private static let vectorDim = 64
    private static let stopWords: Set<String> = ["and", "the", "with", "organic", "raw", "fried", "without", "fat", "pan", "for", "min"]

    private static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var cleaned = ""
        for scalar in lowered.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                cleaned.unicodeScalars.append(scalar)
            } else {
                cleaned.append(" ")
            }
        }
        return cleaned.split(separator: " ").map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) && Double($0) == nil }
    }

    /// `(h * 31 + token.charCodeAt(i)) | 0` - JS 32-bit signed integer wraparound,
    /// reproduced with `Int32` wrapping arithmetic.
    private static func hashToken(_ token: String) -> Int {
        var h: Int32 = 0
        for scalar in token.utf16 {
            h = h &* 31 &+ Int32(scalar)
        }
        return abs(Int(h)) % vectorDim
    }

    /// Name-only, deliberately not name + swiss_category (see source comment on why).
    private static func text(for food: FoodItem) -> String { food.name }

    private static var vectorCache: [String: [Double]] = [:]
    private static let lock = NSLock()

    private static func vector(for food: FoodItem) -> [Double] {
        lock.lock()
        if let cached = vectorCache[food.id] { lock.unlock(); return cached }
        lock.unlock()
        var vec = [Double](repeating: 0, count: vectorDim)
        for token in tokenize(text(for: food)) {
            vec[hashToken(token)] += 1
        }
        lock.lock()
        vectorCache[food.id] = vec
        lock.unlock()
        return vec
    }

    public static func computeVectorSimilarity(_ a: FoodItem, _ b: FoodItem) -> Double {
        let va = vector(for: a)
        let vb = vector(for: b)
        var dot = 0.0, magA = 0.0, magB = 0.0
        for i in 0..<vectorDim {
            dot += va[i] * vb[i]
            magA += va[i] * va[i]
            magB += vb[i] * vb[i]
        }
        if magA == 0 || magB == 0 { return 0 }
        return dot / (magA.squareRoot() * magB.squareRoot())
    }
}
