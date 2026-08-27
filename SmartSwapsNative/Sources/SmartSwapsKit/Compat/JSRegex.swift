import Foundation

/// A regular expression with JavaScript's character-class semantics.
///
/// MEASURED, not assumed. JS `\w` is ASCII-only; ICU's (and therefore
/// NSRegularExpression's) is Unicode-aware, so `\b` disagrees in BOTH directions:
///
///     pattern            subject     JS       ICU
///     /\bäpfel\b/        "äpfel"     false    true
///     /\bmilch\b/        "ämilch"    true     false
///
/// This is load-bearing, not academic: `dietaryFilter.hasWord` runs against `name_de`,
/// which is full of umlauts, and `containsKeywords`, `FUNCTION_REGEXES`, `GROUP_PATTERNS`
/// and `DECLARED_ANIMAL`/`DECLARED_MEAT` all depend on it.
///
/// Every regex in the engine is built through this type. None is handed to
/// NSRegularExpression raw.
public final class JSRegex {

    private let re: NSRegularExpression
    public let source: String

    public init(_ pattern: String, _ flags: String = "") {
        self.source = pattern
        var opts: NSRegularExpression.Options = []
        if flags.contains("i") { opts.insert(.caseInsensitive) }
        if flags.contains("s") { opts.insert(.dotMatchesLineSeparators) }
        if flags.contains("m") { opts.insert(.anchorsMatchLines) }
        let translated = JSRegex.translate(pattern)
        do {
            self.re = try NSRegularExpression(pattern: translated, options: opts)
        } catch {
            fatalError("JSRegex: could not compile \(translated) (from \(pattern)): \(error)")
        }
    }

    // MARK: - JS character classes, spelled out

    /// JS `\w`
    static let wordChars = "A-Za-z0-9_"
    /// JS `\s` - ECMA-262 WhiteSpace + LineTerminator. ICU's `\s` is a different set.
    static let spaceChars = "\\t\\n\\x{0B}\\f\\r \\x{A0}\\x{1680}\\x{2000}-\\x{200A}"
        + "\\x{2028}\\x{2029}\\x{202F}\\x{205F}\\x{3000}\\x{FEFF}"
    /// JS `\d`
    static let digitChars = "0-9"

    /// A JS word boundary: true iff EXACTLY ONE side is an ASCII word character.
    /// Context-free, so it is correct wherever `\b` appears - including immediately
    /// before a non-ASCII literal, which is the case a naive lookaround gets wrong.
    static let wordBoundary =
        "(?:(?<=[\(wordChars)])(?![\(wordChars)])|(?<![\(wordChars)])(?=[\(wordChars)]))"
    static let nonWordBoundary =
        "(?:(?<=[\(wordChars)])(?=[\(wordChars)])|(?<![\(wordChars)])(?![\(wordChars)]))"

    /// Rewrites a JS pattern into an ICU pattern with identical semantics.
    ///
    /// Tracks whether the scanner is inside a `[...]` class, because there `\b` means
    /// backspace and `\w` contributes members rather than being a class of its own.
    static func translate(_ pattern: String) -> String {
        var out = ""
        var inClass = false
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "\\" {
                let next = pattern.index(after: i)
                guard next < pattern.endIndex else { out.append(c); break }
                let e = pattern[next]
                switch e {
                case "w": out += inClass ? wordChars : "[\(wordChars)]"
                case "W": out += inClass ? wordChars : "[^\(wordChars)]"   // see note below
                case "d": out += inClass ? digitChars : "[\(digitChars)]"
                case "D": out += inClass ? digitChars : "[^\(digitChars)]"
                case "s": out += inClass ? spaceChars : "[\(spaceChars)]"
                case "S": out += inClass ? spaceChars : "[^\(spaceChars)]"
                case "b": out += inClass ? "\\b" : wordBoundary            // \b in a class is backspace
                case "B": out += inClass ? "\\B" : nonWordBoundary
                default:
                    out.append(c); out.append(e)
                }
                i = pattern.index(after: next)
                continue
            }
            if c == "[" && !inClass {
                inClass = true
                out.append(c)
                // A leading ^ or ] is literal inside a class; copy it through untouched.
                var j = pattern.index(after: i)
                if j < pattern.endIndex, pattern[j] == "^" { out.append("^"); j = pattern.index(after: j) }
                if j < pattern.endIndex, pattern[j] == "]" { out.append("\\]"); j = pattern.index(after: j) }
                i = j
                continue
            }
            if c == "]" && inClass { inClass = false }
            out.append(c)
            i = pattern.index(after: i)
        }
        return out
    }
    // NOTE on `\W`/`\D`/`\S` inside a class: expanding them to their positive members is
    // wrong in general (it inverts the meaning). Verified that no pattern in this engine
    // does that - the only in-class escapes used are `\w`, `\s` and `\.`, in
    // `[^\w\s]`, `[^\w\säöüß]` and `[^\w\säöüßÄÖÜ]`. A `translate` unit test asserts
    // this stays true, so a future pattern that needs it fails loudly instead of quietly.

    // MARK: - Query

    private func range(_ s: String) -> NSRange { NSRange(s.startIndex..., in: s) }

    /// `regex.test(s)`
    public func test(_ s: String) -> Bool {
        re.firstMatch(in: s, options: [], range: range(s)) != nil
    }

    /// `s.search(regex)` - UTF-16 offset of the first match, or -1.
    public func search(_ s: String) -> Int {
        guard let m = re.firstMatch(in: s, options: [], range: range(s)) else { return -1 }
        return m.range.location
    }

    /// `s.match(regex)` without /g - the full match plus capture groups, nil when no match.
    /// A group that did not participate is nil, matching JS's `undefined`.
    public func match(_ s: String) -> [String?]? {
        guard let m = re.firstMatch(in: s, options: [], range: range(s)) else { return nil }
        return (0..<m.numberOfRanges).map { idx in
            let r = m.range(at: idx)
            guard r.location != NSNotFound, let rr = Range(r, in: s) else { return nil }
            return String(s[rr])
        }
    }

    /// `s.match(regex)` with /g - every full match, or nil when there are none.
    public func matchAll(_ s: String) -> [String]? {
        let ms = re.matches(in: s, options: [], range: range(s))
        if ms.isEmpty { return nil }
        return ms.compactMap { Range($0.range, in: s).map { r in String(s[r]) } }
    }

    /// `s.replace(regex, template)` with /g. `$1`-style references work as in JS.
    public func replaceAll(_ s: String, _ template: String) -> String {
        re.stringByReplacingMatches(in: s, options: [], range: range(s), withTemplate: template)
    }

    /// `s.replace(regex, fn)` with /g.
    public func replaceAll(_ s: String, _ fn: (_ groups: [String?]) -> String) -> String {
        let ms = re.matches(in: s, options: [], range: range(s))
        guard !ms.isEmpty else { return s }
        var out = ""
        var last = s.startIndex
        for m in ms {
            guard let r = Range(m.range, in: s) else { continue }
            out += s[last..<r.lowerBound]
            let groups: [String?] = (0..<m.numberOfRanges).map { idx in
                let gr = m.range(at: idx)
                guard gr.location != NSNotFound, let g = Range(gr, in: s) else { return nil }
                return String(s[g])
            }
            out += fn(groups)
            last = r.upperBound
        }
        out += s[last...]
        return out
    }

    /// `s.replace(regex, replacement)` WITHOUT /g - first match only.
    public func replaceFirst(_ s: String, _ template: String) -> String {
        guard let m = re.firstMatch(in: s, options: [], range: range(s)),
              let r = Range(m.range, in: s) else { return s }
        let replacement = re.replacementString(for: m, in: s, offset: 0, template: template)
        return s.replacingCharacters(in: r, with: replacement)
    }
}
