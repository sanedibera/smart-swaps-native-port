import Foundation

/// Port of `app/engine/produceGroups.ts`.
///
/// A TABLE, NOT A MODEL, and the source explains why with measurements: on hand-labelled
/// produce pairs, embedding cosine ranges 0.71-0.97 for good pairs and 0.60-0.80 for bad
/// ones, and sensory distance 1.4-7.3 vs 1.4-8.1. The ranges overlap almost completely -
/// Tomato->Garlic scores 0.80, higher than half the good pairs. Substitutability is
/// culinary knowledge, not a property of the nutrient vector.
public enum ProduceGroups {

    /// Ordered - first match wins, so narrower patterns come before broader ones.
    /// "Spring onion" before "Onion", "Sweet pepper" before "Pepper".
    private static let GROUP_PATTERNS: [(String, JSRegex)] = [
        // Garlic is deliberately NOT with the onions: it is an aromatic base, not a
        // substitute for a bulb onion, and grouping them is the classic wrong answer
        // this whole table exists to prevent.
        ("ALLIUM_GARLIC",   JSRegex("\\b(?:garlic|wild garlic|ramson)\\b")),
        ("ALLIUM_ONION",    JSRegex("\\b(?:spring onion|shallot|onion|leek|scallion)\\b")),
        // Soft herbs go in at the end and wilt; hard herbs go in early and infuse.
        ("HERB_SOFT",       JSRegex("\\b(?:parsley|basil|chives|coriander|cilantro|dill|chervil|tarragon|mint|lovage)\\b")),
        ("HERB_HARD",       JSRegex("\\b(?:thyme|rosemary|sage|oregano|marjoram|bay leaf)\\b")),
        ("LEAF_COOKING",    JSRegex("\\b(?:spinach|chard|kale|pak choi|beet green)\\b")),
        ("LEAF_SALAD",      JSRegex("\\b(?:lettuce|rocket|arugula|endive|radicchio|watercress|chicory|corn salad)\\b")),
        ("BRASSICA_FLORET", JSRegex("\\b(?:broccoli|cauliflower|romanesco)\\b")),
        ("BRASSICA_HEAD",   JSRegex("\\b(?:cabbage|brussels sprout|kohlrabi)\\b")),
        ("PEPPER_SWEET",    JSRegex("\\bsweet pepper|\\bbell pepper|\\bpaprika pod")),
        ("PEPPER_CHILLI",   JSRegex("\\b(?:chilli|chili|jalapeno|cayenne pod|peperoni)\\b")),
        ("TOMATO",          JSRegex("\\btomato(?:es)?\\b")),
        ("SQUASH_SUMMER",   JSRegex("\\b(?:courgette|zucchini|aubergine|eggplant|patty pan)\\b")),
        ("SQUASH_WINTER",   JSRegex("\\b(?:pumpkin|butternut|squash)\\b")),
        ("CUCUMBER",        JSRegex("\\bcucumber\\b")),
        ("SWEETCORN",       JSRegex("\\b(?:sweetcorn|corn on the cob|maize cob)\\b")),
        ("ROOT_STARCHY",    JSRegex("\\b(?:potato|potatoes|sweet potato|batata|yam|cassava|jerusalem artichoke|topinambur)\\b")),
        ("ROOT_SWEET",      JSRegex("\\b(?:carrot|parsnip|swede|turnip|beetroot|celeriac|salsify)\\b")),
        ("ROOT_PUNGENT",    JSRegex("\\b(?:radish|horseradish|ginger)\\b")),
        // Note the inverted names: this database files green beans as "Bean green, raw"
        // and peas as "Pea green, raw", so both word orders have to be listed.
        ("POD_FRESH",       JSRegex("\\b(?:green bean|bean green|wax bean|broad bean|runner bean|pea green|green pea|sugar pea|mangetout|sugar snap|pea pod)\\b")),
        ("STALK",           JSRegex("\\b(?:asparagus|stalk celery|celery stick|fennel|rhubarb|cardoon)\\b")),
        ("MUSHROOM",        JSRegex("\\b(?:mushroom|chanterelle|porcini|shiitake|oyster mushroom|morel|truffle)\\b")),
        ("CITRUS_SOUR",     JSRegex("\\b(?:lemon|lime)\\b")),
        ("CITRUS_SWEET",    JSRegex("\\b(?:orange|mandarin|clementine|tangerine|grapefruit|pomelo)\\b")),
        ("BERRY",           JSRegex("\\b(?:strawberry|raspberry|blackberry|blueberry|redcurrant|blackcurrant|gooseberry|cranberry|sea buckthorn|elderberry|lingonberry)\\b")),
        ("STONE_FRUIT",     JSRegex("\\b(?:apricot|peach|nectarine|plum|cherry|cherries|mirabelle|damson)\\b")),
        ("POME_FRUIT",      JSRegex("\\b(?:apple|pear|quince)\\b")),
        ("TROPICAL",        JSRegex("\\b(?:mango|papaya|pineapple|passion fruit|kiwi|guava|lychee)\\b")),
        ("MELON",           JSRegex("\\b(?:melon|watermelon|cantaloupe|honeydew)\\b")),
        ("BANANA",          JSRegex("\\bbanana|\\bplantain")),
        ("GRAPE",           JSRegex("\\bgrape\\b")),
        ("POMEGRANATE",     JSRegex("\\bpomegranate\\b")),
        ("AVOCADO",         JSRegex("\\bavocado\\b")),
        ("OLIVE",           JSRegex("\\bolives?\\b")),
    ]

    /// Dried fruit is its own pool regardless of which fruit it came from - a raisin does
    /// not substitute for a fresh grape, but a raisin, a dried apricot and a chopped date
    /// are all doing the same job. Tested before the fresh-fruit patterns.
    private static let DRIED_FRUIT = JSRegex("\\b(?:raisin|sultana|currant dried|date|fig|prune|dried)\\b")
    /// Lemon juice substitutes for lime juice, not for a lemon.
    private static let JUICE = JSRegex("\\bjuice\\b")
    private static let MIXED_VEG = JSRegex("\\bmixed vegetables?\\b")

    /// The substitution group, or nil if this is not produce (or is produce the table
    /// does not cover, which is treated the same way - no swap).
    public static func getProduceGroup(_ food: FoodItem) -> String? {
        let top = String(food.swiss_category.split(separator: "/", omittingEmptySubsequences: false).first ?? "")
        if top != "Vegetables" && top != "Fruit" { return nil }

        let name = food.name.lowercased()

        // A mixed-vegetable pack is not any of the vegetables it names.
        if MIXED_VEG.test(name) { return nil }

        if JUICE.test(name) {
            for (group, pattern) in GROUP_PATTERNS where pattern.test(name) {
                return "JUICE_\(group)"
            }
            return "JUICE_OTHER"
        }
        if DRIED_FRUIT.test(name) { return "FRUIT_DRIED" }

        for (group, pattern) in GROUP_PATTERNS where pattern.test(name) { return group }
        return nil
    }

    /// True when this food is fresh produce, whether or not the table has a group for it.
    public static func isProduce(_ food: FoodItem) -> Bool {
        let top = String(food.swiss_category.split(separator: "/", omittingEmptySubsequences: false).first ?? "")
        return top == "Vegetables" || top == "Fruit"
    }
}
