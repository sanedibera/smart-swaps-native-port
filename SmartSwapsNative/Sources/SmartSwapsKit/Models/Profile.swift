import Foundation

/// `ProfileContext.tsx`'s string-union types. Raw values are the exact JS strings —
/// persisted JSON and `findBestSwaps`' `dietaryPreference: [String]` both need them verbatim.
public enum Sex: String, Codable, CaseIterable, Hashable { case male = "Male", female = "Female" }

public enum ActivityLevel: String, Codable, CaseIterable, Hashable {
    case sedentary = "Sedentary"
    case lightlyActive = "Lightly Active"
    case moderatelyActive = "Moderately Active"
    case veryActive = "Very Active"
    case extraActive = "Extra Active"
}

public enum WeightGoal: String, Codable, CaseIterable, Hashable {
    case lose500 = "-0.5 kg"
    case lose250 = "-0.25 kg"
    case stay = "stay"
    case gain250 = "+0.25 kg"
    case gain500 = "+0.5 kg"
}

public enum DietaryPreference: String, Codable, CaseIterable, Hashable {
    case balanced = "Balanced"
    case highProtein = "High Protein"
    case lowCarb = "Low Carb"
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
}

/// `ProfileContext.tsx`'s `ProfileState`, persisted at `@smart_swaps_profile`.
public struct Profile: Codable, Equatable {
    public var sex: Sex
    public var age: Int
    public var weight: Double
    public var height: Double
    public var activityLevel: ActivityLevel
    public var weightGoal: WeightGoal
    public var dietaryPreference: [DietaryPreference]

    public init(sex: Sex = .female, age: Int = 23, weight: Double = 50, height: Double = 170,
                activityLevel: ActivityLevel = .lightlyActive, weightGoal: WeightGoal = .stay,
                dietaryPreference: [DietaryPreference] = [.balanced]) {
        self.sex = sex
        self.age = age
        self.weight = weight
        self.height = height
        self.activityLevel = activityLevel
        self.weightGoal = weightGoal
        self.dietaryPreference = dietaryPreference
    }

    public static let `default` = Profile()
}

public struct TargetMacros: Equatable {
    public var protein: Int
    public var carbs: Int
    public var fat: Int
    public var sugars: Int
    public var satFat: Int
    public var fiber: Int
    public var salt: Int
}

public struct TargetMacroPercentages: Equatable {
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var sugars: Double
    public var satFat: Double
}

/// Ported from `ProfileContext.tsx`'s `useMemo` block - Mifflin-St Jeor BMR, activity
/// multiplier, weight-goal calorie offset, then a fixed macro split by dietary preference.
public enum ProfileMath {
    public static func targetCalories(for profile: Profile) -> Int {
        var bmr = (10 * profile.weight) + (6.25 * profile.height) - (5 * Double(profile.age))
        bmr += profile.sex == .male ? 5 : -161

        let activityMultipliers: [ActivityLevel: Double] = [
            .sedentary: 1.2, .lightlyActive: 1.375, .moderatelyActive: 1.55,
            .veryActive: 1.725, .extraActive: 1.9,
        ]
        let tdee = bmr * (activityMultipliers[profile.activityLevel] ?? 1.375)

        let goalOffsets: [WeightGoal: Double] = [
            .lose500: -500, .lose250: -250, .stay: 0, .gain250: 250, .gain500: 500,
        ]
        return JSNumber.roundToInt(tdee + (goalOffsets[profile.weightGoal] ?? 0))
    }

    public static func targetMacroPercentages(for profile: Profile) -> TargetMacroPercentages {
        var proteinPct = 0.25, carbsPct = 0.45, fatPct = 0.30
        let prefs = profile.dietaryPreference
        if prefs.contains(.highProtein) {
            proteinPct = 0.35; carbsPct = 0.35; fatPct = 0.30
        } else if prefs.contains(.lowCarb) {
            proteinPct = 0.30; carbsPct = 0.20; fatPct = 0.50
        } else if prefs.contains(.vegetarian) || prefs.contains(.vegan) {
            proteinPct = 0.20; carbsPct = 0.50; fatPct = 0.30
        }
        return TargetMacroPercentages(protein: proteinPct, carbs: carbsPct, fat: fatPct,
                                       sugars: 0.1, satFat: 0.1)
    }

    public static func targetMacros(for profile: Profile) -> TargetMacros {
        let calories = Double(targetCalories(for: profile))
        let pct = targetMacroPercentages(for: profile)
        return TargetMacros(
            protein: JSNumber.roundToInt(calories * pct.protein / 4),
            carbs: JSNumber.roundToInt(calories * pct.carbs / 4),
            fat: JSNumber.roundToInt(calories * pct.fat / 9),
            sugars: JSNumber.roundToInt(calories * 0.1 / 4),
            satFat: JSNumber.roundToInt(calories * 0.1 / 9),
            fiber: JSNumber.roundToInt(calories / 1000 * 14),
            salt: 6
        )
    }
}
