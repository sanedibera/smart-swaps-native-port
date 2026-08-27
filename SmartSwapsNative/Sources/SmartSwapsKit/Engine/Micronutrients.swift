import Foundation

/// Port of `app/engine/micronutrients.ts` (37 ln) - static RDA-style targets by sex, with
/// the exact prose descriptions `NutritionModal` surfaces in its info alerts.
public struct MicronutrientTarget {
    public let key: String
    public let name: String
    public let amount: Double
    public let unit: String
    public let description: String
}

public enum Micronutrients {
    public static func getRecommendedMicros(sex: Sex) -> [MicronutrientTarget] {
        let isMale = sex == .male
        return [
            MicronutrientTarget(key: "vitamin_a_ug", name: "Vitamin A", amount: isMale ? 900 : 700, unit: "µg", description: "Vitamin A is vital for maintaining healthy vision and supporting your immune system. It also plays a critical role in cell growth and maintaining healthy skin and tissues."),
            MicronutrientTarget(key: "betacarotene_ug", name: "Beta-Carotene", amount: 4800, unit: "µg", description: "Beta-Carotene is a powerful antioxidant that your body converts into Vitamin A. It helps protect your cells from damage and supports eye health and immune function."),
            MicronutrientTarget(key: "vitamin_b1_mg", name: "Vitamin B1 (Thiamine)", amount: isMale ? 1.2 : 1.1, unit: "mg", description: "Thiamine is crucial for enabling your body to use carbohydrates as energy. It is also essential for proper nerve function and the metabolism of glucose."),
            MicronutrientTarget(key: "vitamin_b2_mg", name: "Vitamin B2 (Riboflavin)", amount: isMale ? 1.3 : 1.1, unit: "mg", description: "Riboflavin helps break down proteins, fats, and carbohydrates to produce energy. It also maintains healthy skin, eyes, and nerve functions."),
            MicronutrientTarget(key: "vitamin_b6_mg", name: "Vitamin B6", amount: 1.3, unit: "mg", description: "Vitamin B6 is involved in over 100 enzyme reactions, mostly related to protein metabolism. It is important for cognitive development and immune function."),
            MicronutrientTarget(key: "vitamin_b12_ug", name: "Vitamin B12", amount: 2.4, unit: "µg", description: "Vitamin B12 keeps your body's nerve and blood cells healthy. It also helps make DNA and prevents a type of anemia that makes people tired and weak."),
            MicronutrientTarget(key: "niacin_mg", name: "Niacin", amount: isMale ? 16 : 14, unit: "mg", description: "Niacin helps turn the food you eat into the energy you need. It is also important for the development and function of the cells in your body."),
            MicronutrientTarget(key: "folate_ug", name: "Folate", amount: 400, unit: "µg", description: "Folate is essential to produce healthy red blood cells and prevents anemia. It is particularly crucial during periods of rapid growth, such as pregnancy."),
            MicronutrientTarget(key: "pantothenic_acid_mg", name: "Pantothenic Acid", amount: 5, unit: "mg", description: "Pantothenic acid is essential for synthesizing coenzyme-A, which is vital for fatty acid metabolism. It helps your body convert the food you eat into energy."),
            MicronutrientTarget(key: "vitamin_c_mg", name: "Vitamin C", amount: isMale ? 90 : 75, unit: "mg", description: "Vitamin C is an antioxidant that protects your cells against the effects of free radicals. It is also necessary for collagen synthesis and helps your body absorb iron."),
            MicronutrientTarget(key: "vitamin_d_ug", name: "Vitamin D", amount: 15, unit: "µg", description: "Vitamin D promotes calcium absorption in the gut and maintains adequate serum calcium and phosphate concentrations. This is essential for normal bone mineralization and growth."),
            MicronutrientTarget(key: "vitamin_e_mg", name: "Vitamin E", amount: 15, unit: "mg", description: "Vitamin E is a fat-soluble antioxidant that stops the production of free radicals. It also plays a role in immune function and cellular signaling."),
            MicronutrientTarget(key: "sodium_mg", name: "Sodium", amount: 1500, unit: "mg", description: "Sodium is necessary for muscle contraction and nerve cell transmission. It also regulates the balance of fluids in your body."),
            MicronutrientTarget(key: "potassium_mg", name: "Potassium", amount: isMale ? 3400 : 2600, unit: "mg", description: "Potassium helps maintain normal levels of fluid inside our cells. It also helps muscles contract and supports healthy blood pressure."),
            MicronutrientTarget(key: "chloride_mg", name: "Chloride", amount: 2300, unit: "mg", description: "Chloride is one of the most important electrolytes in the blood. It helps keep the amount of fluid inside and outside of your cells in balance."),
            MicronutrientTarget(key: "calcium_mg", name: "Calcium", amount: 1000, unit: "mg", description: "Calcium is the most abundant mineral in the body, vital for bone and teeth health. It also plays a crucial role in heart rhythm, muscle function, and nerve signaling."),
            MicronutrientTarget(key: "magnesium_mg", name: "Magnesium", amount: isMale ? 400 : 310, unit: "mg", description: "Magnesium acts as a cofactor in more than 300 enzyme systems regulating diverse biochemical reactions. It is important for muscle and nerve function, and blood glucose control."),
            MicronutrientTarget(key: "phosphorus_mg", name: "Phosphorus", amount: 700, unit: "mg", description: "Phosphorus works with calcium to help build bones and teeth. It is also needed for the body to make protein for growth, maintenance, and repair of cells."),
            MicronutrientTarget(key: "iron_mg", name: "Iron", amount: isMale ? 8 : 18, unit: "mg", description: "Iron is an essential component of hemoglobin, a red blood cell protein that transfers oxygen from the lungs to the tissues. Adequate iron is critical to prevent fatigue."),
            MicronutrientTarget(key: "iodide_ug", name: "Iodide", amount: 150, unit: "µg", description: "Iodine is needed by the cells to change food into energy. It also is necessary for normal thyroid function, and for the production of thyroid hormones."),
            MicronutrientTarget(key: "zinc_mg", name: "Zinc", amount: isMale ? 11 : 8, unit: "mg", description: "Zinc is a nutrient that people need to stay healthy, found in cells throughout the body. It helps the immune system fight off invading bacteria and viruses."),
        ]
    }
}
