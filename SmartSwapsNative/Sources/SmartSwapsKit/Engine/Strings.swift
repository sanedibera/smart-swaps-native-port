import Foundation

/// `normalize`, `asciiFold` and `levenshtein` from `app/engine/receiptParser.ts`.
///
/// Split into their own file because `foodIndex.ts` imports the first two and the whole
/// retrieval stage depends on them producing byte-identical output for German text.
public enum EngineStrings {

    // Compiled once. The TS module-level regex literals are compiled once by V8 too.
    private static let reDiacritic = JSRegex("\\p{Diacritic}", "gu")
    private static let rePunctToSpace = JSRegex("[\\.\\-/]", "g")
    private static let reNonWordKeepUmlaut = JSRegex("[^\\w\\säöüß]", "gi")
    private static let reNonWord = JSRegex("[^\\w\\s]", "g")
    private static let reWhitespaceRun = JSRegex("\\s+", "g")

    /// JS `String.prototype.trim` - ECMA WhiteSpace + LineTerminator, which is not
    /// identical to Swift's `.whitespacesAndNewlines`.
    static let jsWhitespace = CharacterSet(charactersIn:
        "\u{09}\u{0A}\u{0B}\u{0C}\u{0D}\u{20}\u{A0}\u{1680}"
        + "\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}"
        + "\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")

    @inline(__always)
    static func jsTrim(_ s: String) -> String { s.trimmingCharacters(in: jsWhitespace) }

    /// Keeps German umlauts and eszett, strips every other diacritic.
    ///
    /// The placeholder dance is in the source and is load-bearing: NFD + diacritic-strip
    /// would otherwise turn "ä" into "a", so the four German letters are parked behind
    /// sentinels first and restored after.
    public static func normalize(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "ä", with: "__AUM__")
        s = s.replacingOccurrences(of: "ö", with: "__OUM__")
        s = s.replacingOccurrences(of: "ü", with: "__UUM__")
        s = s.replacingOccurrences(of: "ß", with: "__SZ__")
        s = s.decomposedStringWithCanonicalMapping
        s = reDiacritic.replaceAll(s, "")
        s = s.replacingOccurrences(of: "__AUM__", with: "ä")
        s = s.replacingOccurrences(of: "__OUM__", with: "ö")
        s = s.replacingOccurrences(of: "__UUM__", with: "ü")
        s = s.replacingOccurrences(of: "__SZ__", with: "ß")
        s = rePunctToSpace.replaceAll(s, " ")
        s = reNonWordKeepUmlaut.replaceAll(s, " ")
        s = reWhitespaceRun.replaceAll(s, " ")
        return jsTrim(s)
    }

    /// Folds German letters to their ASCII digraphs, then strips remaining diacritics.
    public static func asciiFold(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "ä", with: "ae")
        s = s.replacingOccurrences(of: "ö", with: "oe")
        s = s.replacingOccurrences(of: "ü", with: "ue")
        s = s.replacingOccurrences(of: "ß", with: "ss")
        s = s.decomposedStringWithCanonicalMapping
        s = reDiacritic.replaceAll(s, "")
        s = rePunctToSpace.replaceAll(s, " ")
        s = reNonWord.replaceAll(s, " ")
        s = reWhitespaceRun.replaceAll(s, " ")
        return jsTrim(s)
    }

    /// `s.split(/\s+/)` with JS semantics: a leading separator yields a leading "".
    public static func splitWhitespace(_ s: String) -> [String] {
        if s.isEmpty { return [""] }
        var out: [String] = []
        var current = ""
        var inRun = false
        for ch in s.unicodeScalars {
            if jsWhitespace.contains(ch) {
                if !inRun { out.append(current); current = ""; inRun = true }
            } else {
                current.unicodeScalars.append(ch)
                inRun = false
            }
        }
        out.append(current)
        return out
    }

    /// Levenshtein distance, operating on UTF-16 code units to match JS `charAt`.
    ///
    /// The TS version indexes with `charAt`, which is a UTF-16 unit - not a grapheme.
    /// Every string reaching it here is normalized German/ASCII where the two coincide,
    /// but matching the unit exactly costs nothing and removes a whole class of doubt.
    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let av = Array(a.utf16), bv = Array(b.utf16)
        let an = av.count, bn = bv.count
        if an == 0 { return bn }
        if bn == 0 { return an }
        var prev = Array(0...an)
        var cur = [Int](repeating: 0, count: an + 1)
        for i in 1...bn {
            cur[0] = i
            for j in 1...an {
                if bv[i - 1] == av[j - 1] {
                    cur[j] = prev[j - 1]
                } else {
                    cur[j] = Swift.min(prev[j - 1] + 1, cur[j - 1] + 1, prev[j] + 1)
                }
            }
            swap(&prev, &cur)
        }
        return prev[an]
    }
}
