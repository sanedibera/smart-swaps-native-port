import Foundation

/// Port of `app/engine/dietaryFilter.ts`.
///
/// DELIBERATELY BIASED TOWARD EXCLUSION, per the source: wrongly hiding a vegan food
/// costs one suggestion, wrongly showing pork to a vegan is a product failure. The
/// keyword lists are broad on purpose.
///
/// This module is the one most exposed to the `\b` trap - `hasWord` runs against
/// `name_de`, which is full of umlauts, where ICU's Unicode-aware word boundary and
/// JS's ASCII one disagree in both directions. Everything goes through JSRegex.
public enum DietaryFilter {

    /// Whole-word matcher. Regex cached per word list, matching the TS `WORD_REGEX_CACHE`
    /// - this runs once per candidate per swap lookup and the source measured it as hot.
    private static func hasWord(_ str: String, _ regex: JSRegex) -> Bool {
        regex.test(str.lowercased())
    }

    private static func buildRegex(_ words: [String]) -> JSRegex {
        let escaped = words.map { escapeRegex($0) }
        return JSRegex("\\b(?:" + escaped.joined(separator: "|") + ")\\b")
    }

    /// `w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')`
    static func escapeRegex(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ".*+?^${}()|[]\\".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    // Same list as getEquivalenceGroup's PLANT_ALT_KEYWORDS, and for the same reason:
    // "substitute"/"alternative" are excluded because in this database they attach to a
    // different noun as often as to the food class ("Coffee substitute with milk").
    static let PLANT_ALT = ["vegan", "plant-based", "plant based", "tofu", "seitan",
                            "soy", "soya", "texturised", "texturized"]

    static let MEAT_CATEGORIES = ["meat and meat products"]
    static let FISH_CATEGORIES = ["fish and seafood", "fish"]
    static let DAIRY_CATEGORIES = ["milk and dairy products"]

    static let MEAT_WORDS = [
        "meat", "beef", "pork", "veal", "lamb", "mutton", "goat", "venison", "game",
        "chicken", "poultry", "turkey", "duck", "goose", "rabbit", "hare",
        "ham", "bacon", "sausage", "salami", "mince", "minced", "wurst", "bratwurst",
        "liver", "kidney", "heart", "tripe", "offal", "blood", "brawn", "pate",
        "lard", "tallow", "dripping", "gelatine", "gelatin", "bologna", "pastrami",
        "prosciutto", "chorizo", "pepperoni", "schnitzel", "meatball", "burger patty",
    ]

    static let FISH_WORDS = [
        "fish", "salmon", "tuna", "cod", "haddock", "herring", "mackerel", "sardine",
        "anchovy", "trout", "carp", "pike", "perch", "plaice", "sole", "halibut",
        "whiting", "pollack", "saithe", "eel", "bass", "bream", "albacore",
        "shrimp", "prawn", "crab", "lobster", "crayfish", "mussel", "oyster", "clam",
        "squid", "octopus", "scallop", "caviar", "roe", "seafood", "surimi",
    ]

    static let DAIRY_WORDS = [
        "milk", "cheese", "butter", "cream", "yoghurt", "yogurt", "quark", "curd",
        "whey", "skyr", "kefir", "ghee", "mozzarella", "ricotta", "parmesan", "feta",
        "camembert", "brie", "gouda", "cheddar", "emmentaler", "mascarpone", "lactose",
    ]

    static let EGG_WORDS = ["egg", "eggs", "mayonnaise", "meringue", "albumen"]
    static let OTHER_ANIMAL_WORDS = ["honey", "beeswax", "propolis", "royal jelly", "carmine", "shellac"]

    private static let rePlantAlt = buildRegex(PLANT_ALT)
    private static let reMeat = buildRegex(MEAT_WORDS)
    private static let reFish = buildRegex(FISH_WORDS)
    private static let reDairy = buildRegex(DAIRY_WORDS)
    private static let reEgg = buildRegex(EGG_WORDS)
    private static let reOtherAnimal = buildRegex(OTHER_ANIMAL_WORDS)

    /// Bounded to 40 characters and stopped at ; or brackets - NOT at commas, because an
    /// ingredient list is comma-separated by nature.
    private static let DECLARED_ANIMAL = JSRegex(
        "\\b(containing|contains|with)\\b[^;()]{0,40}\\b(milk|egg|eggs|cheese|butter|cream|honey|whey|lactose|gelatine|gelatin)\\b", "i")
    private static let DECLARED_MEAT = JSRegex(
        "\\b(containing|contains|with)\\b[^;()]{0,40}\\b(meat|beef|pork|chicken|poultry|ham|bacon|fish|gelatine|gelatin|lard)\\b", "i")

    private static func inCategory(_ food: FoodItem, _ prefixes: [String]) -> Bool {
        let cat = food.swiss_category.lowercased()
        return prefixes.contains { cat.hasPrefix($0) }
    }

    /// True when the food is explicitly a plant-based substitute product.
    public static func isPlantAlternative(_ food: FoodItem) -> Bool {
        hasWord(food.name, rePlantAlt) || hasWord(food.name_de ?? "", rePlantAlt)
    }

    /// Contains meat or fish.
    public static func containsMeatOrFish(_ food: FoodItem) -> Bool {
        let text = "\(food.name) \(food.name_de ?? "")"
        // Declared ingredients are checked BEFORE the plant-alternative exemption, so a
        // product cannot market itself past its own ingredient list.
        if DECLARED_MEAT.test(text) { return true }
        if isPlantAlternative(food) { return false }
        if inCategory(food, MEAT_CATEGORIES + FISH_CATEGORIES) { return true }
        return hasWord(text, reMeat) || hasWord(text, reFish)
    }

    /// Contains dairy, egg, honey or another animal-derived ingredient.
    public static func containsAnimalProduct(_ food: FoodItem) -> Bool {
        let text = "\(food.name) \(food.name_de ?? "")"
        if DECLARED_ANIMAL.test(text) || DECLARED_MEAT.test(text) { return true }
        if containsMeatOrFish(food) { return true }
        if isPlantAlternative(food) { return false }
        if inCategory(food, DAIRY_CATEGORIES) { return true }
        return hasWord(text, reDairy) || hasWord(text, reEgg) || hasWord(text, reOtherAnimal)
    }

    /// Unknown preference strings are permissive - a typo or a future preference should
    /// not silently empty every user's suggestions.
    public static func isAllowedForDiet(_ food: FoodItem, _ preferences: [String]) -> Bool {
        if preferences.contains("Vegan") { return !containsAnimalProduct(food) }
        if preferences.contains("Vegetarian") { return !containsMeatOrFish(food) }
        return true
    }
}
