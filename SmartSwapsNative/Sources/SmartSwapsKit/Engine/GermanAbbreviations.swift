import Foundation

/// Port of `app/engine/germanAbbreviations.ts`.
public enum GermanAbbreviations {

    public static let BRAND_STRIP_LIST = [
        "gran",       // e.g. Grandiso
        "grandiso",
        "grop",       // e.g. Gropper
        "m.i.",
        "m.i",
        "mi",
        "bistro",
        "ostmann",    // spice/herb-only brand; never a hint towards another food category
    ]

    public static let CERTIFICATIONS = [
        "ogt",        // ohne Gentechnik
        "vlog",
        "bio",
    ]

    /// Keys with dots can never match, because dots are stripped before this lookup runs.
    /// Preserved anyway - removing them would be a behaviour change with no upside.
    public static let ABBREVIATIONS: [String: String] = [
        "jogh": "joghurt", "sort": "sortiert", "sort.": "sortiert",
        "clas": "classic", "clas.": "classic",
        "pr": "protein", "pu": "pudding", "mozz": "mozzarella",
        "nozz": "mozzarella",      // common OCR m->n misread
        "pfann": "pfannengericht", "sojajogh": "soja joghurt",
        "sojadr": "soja joghurt drink", "moz": "mozzarella", "skr": "skyr",
        "himb": "himbeere", "cranb": "cranberry", "pudd": "pudding",
        "brocc": "brokkoli", "erdbe": "erdbeere", "heidelbe": "heidelbeere",
        "himbe": "himbeere", "geflueg": "gefluegel", "put": "pute",
        "gem": "gemischt",         // e.g. "Hackfleisch gem."
        // Added from frequency analysis of the 568-row labeled receipt dataset, each
        // verified against real receipt context. Keys are dot-free.
        "hähn": "hähnchen", "tom": "tomate", "rogg": "roggen", "koff": "koffein",
        "prot": "protein", "norweg": "norwegisch", "leberw": "leberwurst",
        "schlagsa": "schlagsahne",
    ]

    public static let LOANWORD_SYNONYMS: [String: String] = [
        "fusilli": "teigwaren pasta", "nudeln": "teigwaren pasta",
        "maccheroni": "teigwaren pasta", "aceto": "essig", "balsamico": "essig balsam",
        "arrabbiata": "tomatensauce scharf", "arrabiat": "tomatensauce scharf",
        "penne": "teigwaren pasta", "spaghetti": "teigwaren pasta",
        "tagliatelle": "teigwaren pasta", "lady": "apfel apple",
        "braeburn": "apfel apple", "elstar": "apfel apple", "jonagold": "apfel apple",
        "boskoop": "apfel apple", "pinova": "apfel apple",
        "grana": "parmesan hartkaese", "para": "parmesan", "parmigiano": "parmesan",
        "tomme": "kaese cheese", "blanche": "kaese cheese",
        "pestu": "pesto",          // common OCR misread
        "diavolo": "pizza scharfe salami", "reggiano": "parmesan hartkaese",
        // Deliberately no brand->product mappings for snack brands: expanding Pringles to
        // "chips kartoffel" lets bare "kartoffel" match "Kartoffel geschält, roh" at 0.75,
        // which outscores the chips entry - turning a silent MISS into a confident WRONG.
        "ravioli": "teigwaren pasta", "angus": "rind beef",
        "pfefferkoer": "pfefferkoerner pfeffer",
        "suppengemuese": "suppengruen gemuese", "innenfilet": "filet brustfilet",
    ]

    private static let reDotDash = JSRegex("[\\.\\-]", "g")
    private static let reLetterDigit = JSRegex("([a-zäöüßA-ZÄÖÜ])(\\d)", "g")
    private static let rePunct = JSRegex("[^\\w\\säöüßÄÖÜ]", "g")
    private static let reBioBio = JSRegex("\\bbio\\s*bio\\b", "gi")
    private static let prefixesToSplit = ["protein", "schoko", "bistro", "mini", "bio", "vegan", "veggie"]
    private static let prefixRegexes: [JSRegex] = prefixesToSplit.map { JSRegex("\\b(\($0))", "gi") }
    private static let dessertTokens: Set<String> = ["pudding", "dessert", "joghurt", "jogh", "pu", "pu."]

    /// Normalizes a German receipt line by expanding abbreviations, stripping brands and
    /// certifications, and applying context-dependent rules.
    public static func expandGermanAbbreviations(_ line: String) -> String {
        var cleanLine = reDotDash.replaceAll(line, " ")

        // Receipts glue the pack size onto the product word ("Penne500g"). Split on the
        // letter->digit boundary only: the reverse would tear "500g" into "500 g" and
        // strand a bare unit token for no gain.
        cleanLine = reLetterDigit.replaceAll(cleanLine, "$1 $2")

        // Split common compound prefixes so they tokenize separately. Only NON-FOOD
        // qualifiers belong here: in a German compound the LAST element is the head noun,
        // so splitting "Chiliflocken" would expose "chili" as a standalone exact match
        // while the real head ("flocken") goes unmatched.
        for re in prefixRegexes { cleanLine = re.replaceAll(cleanLine, "$1 ") }

        cleanLine = rePunct.replaceAll(cleanLine, " ")
        cleanLine = reBioBio.replaceAll(cleanLine, "bio")

        var tokens = EngineStrings.splitWhitespace(cleanLine).filter { !$0.isEmpty }

        // Context-dependent rules BEFORE generic lowercasing/expansion.
        let hasDessertContext = tokens.contains { dessertTokens.contains($0.lowercased()) }
        tokens = tokens.map { token in
            if token == "Gr" || token == "Gr." { if hasDessertContext { return "Grieß" } }
            return token
        }

        var normalizedTokens: [String] = []
        for token in tokens {
            let lowerToken = token.lowercased()
            if BRAND_STRIP_LIST.contains(lowerToken) { continue }
            if CERTIFICATIONS.contains(lowerToken) { continue }
            if let expansion = ABBREVIATIONS[lowerToken] {
                normalizedTokens.append(expansion)
                continue
            }
            if let syn = LOANWORD_SYNONYMS[lowerToken] {
                normalizedTokens.append(token)
                normalizedTokens.append(syn)
                continue
            }
            normalizedTokens.append(token)
        }
        return normalizedTokens.joined(separator: " ")
    }
}
