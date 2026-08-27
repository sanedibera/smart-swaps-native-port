import Foundation

/// `app/types.ts` FoodNutrients.micros - 21 fixed keys, all Double.
public struct Micros: Codable, Equatable {
    public var vitamin_a_ug = 0.0
    public var betacarotene_ug = 0.0
    public var vitamin_b1_mg = 0.0
    public var vitamin_b2_mg = 0.0
    public var vitamin_b6_mg = 0.0
    public var vitamin_b12_ug = 0.0
    public var niacin_mg = 0.0
    public var folate_ug = 0.0
    public var pantothenic_acid_mg = 0.0
    public var vitamin_c_mg = 0.0
    public var vitamin_d_ug = 0.0
    public var vitamin_e_mg = 0.0
    public var sodium_mg = 0.0
    public var potassium_mg = 0.0
    public var chloride_mg = 0.0
    public var calcium_mg = 0.0
    public var magnesium_mg = 0.0
    public var phosphorus_mg = 0.0
    public var iron_mg = 0.0
    public var iodide_ug = 0.0
    public var zinc_mg = 0.0

    public init() {}

    /// The DB column is a JSON string, and it is `{}` for some rows. A missing key reads
    /// as 0, matching `scaleNutrients`'s `?? 0` and `mapFoodRow`'s `: {}`.
    public init(json: [String: Double]) {
        vitamin_a_ug = json["vitamin_a_ug"] ?? 0
        betacarotene_ug = json["betacarotene_ug"] ?? 0
        vitamin_b1_mg = json["vitamin_b1_mg"] ?? 0
        vitamin_b2_mg = json["vitamin_b2_mg"] ?? 0
        vitamin_b6_mg = json["vitamin_b6_mg"] ?? 0
        vitamin_b12_ug = json["vitamin_b12_ug"] ?? 0
        niacin_mg = json["niacin_mg"] ?? 0
        folate_ug = json["folate_ug"] ?? 0
        pantothenic_acid_mg = json["pantothenic_acid_mg"] ?? 0
        vitamin_c_mg = json["vitamin_c_mg"] ?? 0
        vitamin_d_ug = json["vitamin_d_ug"] ?? 0
        vitamin_e_mg = json["vitamin_e_mg"] ?? 0
        sodium_mg = json["sodium_mg"] ?? 0
        potassium_mg = json["potassium_mg"] ?? 0
        chloride_mg = json["chloride_mg"] ?? 0
        calcium_mg = json["calcium_mg"] ?? 0
        magnesium_mg = json["magnesium_mg"] ?? 0
        phosphorus_mg = json["phosphorus_mg"] ?? 0
        iron_mg = json["iron_mg"] ?? 0
        iodide_ug = json["iodide_ug"] ?? 0
        zinc_mg = json["zinc_mg"] ?? 0
    }

    /// Iteration order matters: `food/[id].tsx` renders `Object.entries(nutrients.micros)`,
    /// and JS object key order here is the literal order in `types.ts`.
    public static let keysInDeclarationOrder = [
        "vitamin_a_ug", "betacarotene_ug", "vitamin_b1_mg", "vitamin_b2_mg", "vitamin_b6_mg",
        "vitamin_b12_ug", "niacin_mg", "folate_ug", "pantothenic_acid_mg", "vitamin_c_mg",
        "vitamin_d_ug", "vitamin_e_mg", "sodium_mg", "potassium_mg", "chloride_mg",
        "calcium_mg", "magnesium_mg", "phosphorus_mg", "iron_mg", "iodide_ug", "zinc_mg",
    ]

    public subscript(key: String) -> Double {
        get {
            switch key {
            case "vitamin_a_ug": return vitamin_a_ug
            case "betacarotene_ug": return betacarotene_ug
            case "vitamin_b1_mg": return vitamin_b1_mg
            case "vitamin_b2_mg": return vitamin_b2_mg
            case "vitamin_b6_mg": return vitamin_b6_mg
            case "vitamin_b12_ug": return vitamin_b12_ug
            case "niacin_mg": return niacin_mg
            case "folate_ug": return folate_ug
            case "pantothenic_acid_mg": return pantothenic_acid_mg
            case "vitamin_c_mg": return vitamin_c_mg
            case "vitamin_d_ug": return vitamin_d_ug
            case "vitamin_e_mg": return vitamin_e_mg
            case "sodium_mg": return sodium_mg
            case "potassium_mg": return potassium_mg
            case "chloride_mg": return chloride_mg
            case "calcium_mg": return calcium_mg
            case "magnesium_mg": return magnesium_mg
            case "phosphorus_mg": return phosphorus_mg
            case "iron_mg": return iron_mg
            case "iodide_ug": return iodide_ug
            case "zinc_mg": return zinc_mg
            default: return 0
            }
        }
        set {
            switch key {
            case "vitamin_a_ug": vitamin_a_ug = newValue
            case "betacarotene_ug": betacarotene_ug = newValue
            case "vitamin_b1_mg": vitamin_b1_mg = newValue
            case "vitamin_b2_mg": vitamin_b2_mg = newValue
            case "vitamin_b6_mg": vitamin_b6_mg = newValue
            case "vitamin_b12_ug": vitamin_b12_ug = newValue
            case "niacin_mg": niacin_mg = newValue
            case "folate_ug": folate_ug = newValue
            case "pantothenic_acid_mg": pantothenic_acid_mg = newValue
            case "vitamin_c_mg": vitamin_c_mg = newValue
            case "vitamin_d_ug": vitamin_d_ug = newValue
            case "vitamin_e_mg": vitamin_e_mg = newValue
            case "sodium_mg": sodium_mg = newValue
            case "potassium_mg": potassium_mg = newValue
            case "chloride_mg": chloride_mg = newValue
            case "calcium_mg": calcium_mg = newValue
            case "magnesium_mg": magnesium_mg = newValue
            case "phosphorus_mg": phosphorus_mg = newValue
            case "iron_mg": iron_mg = newValue
            case "iodide_ug": iodide_ug = newValue
            case "zinc_mg": zinc_mg = newValue
            default: break
            }
        }
    }
}

public struct FoodNutrients: Codable, Equatable {
    public var kcal = 0.0
    public var protein_g = 0.0
    public var carbs_g = 0.0
    public var sugars_g = 0.0
    public var fat_g = 0.0
    public var saturated_fat_g = 0.0
    public var fiber_g = 0.0
    public var salt_g = 0.0
    public var micros = Micros()
    public init() {}
}

/// A food.
///
/// A CLASS, not a struct, and that is load-bearing. `matchFoodToOcrText` keys a
/// `Map<FoodItem, number>` on the object itself and calls `addCand(f)` twice to
/// double-weight an exact hit; `foodIndex` builds `Map<string, Set<FoodItem>>` whose
/// membership is by identity. A struct has no identity, and copying 7,140 of them through
/// every filter chain would be gratuitous besides. Reference semantics here are the
/// faithful translation of a JS object reference, not a convenience.
public final class FoodItem {
    public let id: String
    public let name: String
    public let name_de: String?
    public let category: String
    public let swiss_category: String
    public let health_score: Double
    public let nutri_grade: String?
    public let nova_group: Int?
    public let swap_suggestion_id: String?
    public let icon_key: String?
    public let nutrients_per_100: FoodNutrients

    public init(id: String, name: String, name_de: String?, category: String,
                swiss_category: String, health_score: Double, nutri_grade: String?,
                nova_group: Int?, swap_suggestion_id: String?, icon_key: String?,
                nutrients_per_100: FoodNutrients) {
        self.id = id
        self.name = name
        self.name_de = name_de
        self.category = category
        self.swiss_category = swiss_category
        self.health_score = health_score
        self.nutri_grade = nutri_grade
        self.nova_group = nova_group
        self.swap_suggestion_id = swap_suggestion_id
        self.icon_key = icon_key
        self.nutrients_per_100 = nutrients_per_100
    }
}

extension FoodItem: Hashable {
    /// Identity, matching JS object-reference equality.
    public static func == (a: FoodItem, b: FoodItem) -> Bool { a === b }
    public func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}
