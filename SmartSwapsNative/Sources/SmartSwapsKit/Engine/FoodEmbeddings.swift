import Foundation

/// Port of `app/engine/foodEmbeddings.ts`.
///
/// The base64 payload is unpacked to a raw .bin at build time (Tools/convert-assets.py)
/// rather than decoded in-process, so the hand-rolled Hermes base64 decoder has no Swift
/// counterpart. The numbers are untouched, and Phase 3 proves it: every cosine is diffed
/// against the TS engine's to 1e-9.
public enum FoodEmbeddings {

    private struct Meta: Decodable {
        let model: String
        let dim: Int
        let count: Int
        let ids: [String]
        let scales: [Double]
    }

    private static let state: (quant: [Int8], index: [String: Int], dim: Int, scales: [Double], model: String) = {
        let meta = try! JSONDecoder().decode(
            Meta.self, from: Data(contentsOf: Resources.url("foodEmbeddings.meta.json")))
        let raw = try! Data(contentsOf: Resources.url("foodEmbeddings.bin"), options: .mappedIfSafe)
        precondition(raw.count == meta.count * meta.dim, "embedding payload size mismatch")
        let quant = raw.withUnsafeBytes { [Int8]($0.bindMemory(to: Int8.self)) }
        var index = [String: Int](minimumCapacity: meta.ids.count)
        for (i, id) in meta.ids.enumerated() { index[id] = i }
        return (quant, index, meta.dim, meta.scales, meta.model)
    }()

    public static var model: String { state.model }

    /// Cosine similarity in [-1,1], or nil when either food has no embedding.
    ///
    /// nil is NOT 0 and must propagate: the GBM carries a learned default branch per
    /// split, so an unembedded food degrades gracefully, whereas a fabricated 0 asserts
    /// "unrelated", which is a different and false claim.
    public static func embeddingCosine(_ idA: String, _ idB: String) -> Double? {
        let s = state
        guard let ia = s.index[idA], let ib = s.index[idB] else { return nil }
        let dim = s.dim
        let baseA = ia * dim, baseB = ib * dim
        var dot = 0.0
        s.quant.withUnsafeBufferPointer { q in
            // Accumulated as Double from the first term, matching JS where every
            // intermediate is a Double. An Int accumulator would be exact but would
            // round differently on the final scale multiply.
            for i in 0..<dim { dot += Double(q[baseA + i]) * Double(q[baseB + i]) }
        }
        return dot * s.scales[ia] * s.scales[ib]
    }

    public static func hasEmbedding(_ id: String) -> Bool { state.index[id] != nil }
}

/// Bundle lookup shared by the asset-backed engine modules.
enum Resources {
    static func url(_ name: String) -> URL {
        guard let u = Bundle.module.url(forResource: "Resources/\(name)", withExtension: nil)
                ?? Bundle.module.url(forResource: name, withExtension: nil) else {
            fatalError("resource missing from bundle: \(name)")
        }
        return u
    }
    static func data(_ name: String) -> Data { try! Data(contentsOf: url(name)) }
}
