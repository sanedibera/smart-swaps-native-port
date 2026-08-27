import Foundation

/// Port of `app/engine/foodAttributes.ts`.
public struct FoodAttributes {
    public let sensory: [Int]      // 8 axes, order = asset.sensoryAxes, each 0-10
    public let culinaryRole: Int   // index into roles, or -1
    public let prepState: Int      // index into prep, or -1
    public let glycemicLoad: Int   // 0 low, 1 medium, 2 high
    public let satiety: Int
    public let caffeine: Bool
    public let alcohol: Bool
    public let timeOfDayMask: Int
}

public enum FoodAttributesStore {

    private struct Meta: Decodable {
        let count: Int
        let bytesPerFood: Int
        let roles: [String]
        let prep: [String]
        let levels: [String]
        let times: [String]
        let sensoryAxes: [String]
        let ids: [String]
    }

    private static let state: (raw: [UInt8], index: [String: Int], meta: Meta) = {
        let meta = try! JSONDecoder().decode(
            Meta.self, from: Data(contentsOf: Resources.url("foodAttributes.meta.json")))
        let data = try! Data(contentsOf: Resources.url("foodAttributes.bin"), options: .mappedIfSafe)
        precondition(data.count == meta.count * meta.bytesPerFood, "attribute payload size mismatch")
        var index = [String: Int](minimumCapacity: meta.ids.count)
        for (i, id) in meta.ids.enumerated() { index[id] = i }
        return ([UInt8](data), index, meta)
    }()

    /// Attributes for a food id, or nil. nil is deliberate and must be propagated, not
    /// defaulted - zeros would assert "no sweetness, no saltiness, raw produce".
    public static func getAttributes(_ id: String) -> FoodAttributes? {
        let s = state
        guard let idx = s.index[id] else { return nil }
        let o = idx * s.meta.bytesPerFood
        let b = s.raw
        var sensory = [Int](repeating: 0, count: 8)
        for k in 0..<8 { sensory[k] = Int(b[o + k]) }
        return FoodAttributes(
            sensory: sensory,
            culinaryRole: b[o + 8] == 255 ? -1 : Int(b[o + 8]),
            prepState: b[o + 9] == 255 ? -1 : Int(b[o + 9]),
            glycemicLoad: Int(b[o + 10]),
            satiety: Int(b[o + 11]),
            caffeine: b[o + 12] == 1,
            alcohol: b[o + 13] == 1,
            timeOfDayMask: Int(b[o + 14])
        )
    }

    public static func hasAttributes(_ id: String) -> Bool { state.index[id] != nil }

    public static var TIME_LABELS: [String] { state.meta.times }
    public static var ROLE_LABELS: [String] { state.meta.roles }
    public static var PREP_LABELS: [String] { state.meta.prep }
    public static var SENSORY_AXES: [String] { state.meta.sensoryAxes }
}
