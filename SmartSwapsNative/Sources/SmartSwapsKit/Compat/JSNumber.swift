import Foundation

/// JavaScript numeric semantics that Swift does not share.
///
/// Every one of these was measured against the running TS engine before being written -
/// none is defensive. See PORTING_INVENTORY.md §5.2.
public enum JSNumber {

    /// `Math.round`. Ties go toward +infinity, NOT away from zero.
    ///
    ///     JS      Math.round(-2.5) === -2
    ///     Swift   (-2.5).rounded() ==  -3
    ///
    /// Reachable: `evaluateSwap` deltas and `NutrientRow.pct` both take negatives.
    @inlinable
    public static func round(_ x: Double) -> Double {
        if x.isNaN || x.isInfinite { return x }
        // Above 2^52 every Double is already integral and `x + 0.5` would lose the bit.
        if x >= 4503599627370496.0 || x <= -4503599627370496.0 { return x }
        let r = (x + 0.5).rounded(.down)
        // Guard the one input where `x + 0.5` rounds up before the floor sees it:
        // 0.49999999999999994 + 0.5 == 1.0 exactly, but Math.round gives 0.
        return (r - x > 0.5) ? r - 1 : r
    }

    /// `Math.round` where the caller wants an Int (display paths only).
    @inlinable
    public static func roundToInt(_ x: Double) -> Int {
        let r = round(x)
        if r.isNaN { return 0 }
        return Int(r.clamped(to: -9.007199254740991e15 ... 9.007199254740991e15))
    }

    /// JS `||` on a Double: returns `fallback` when `primary` is falsy (0, -0, NaN).
    ///
    /// Used by comparators written as `a - b || c - d`, where a zero *or NaN* first
    /// term must fall through to the second.
    @inlinable
    public static func or(_ primary: Double, _ fallback: @autoclosure () -> Double) -> Double {
        (primary == 0 || primary.isNaN) ? fallback() : primary
    }

    /// `Number.prototype.toString()` with no radix - ECMA-262 7.1.12.1.
    ///
    /// Needed because `food/[id].tsx` renders `{value}{unit}` with no formatting, so a
    /// nutrient of 3.4000000000000004 prints in full. Swift's `Double.description` is also
    /// shortest-round-trip but renders integers as "3.0" and exponents as "1e-07".
    public static func toString(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d == 0 { return "0" }                      // JS: String(-0) === "0"
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }

        let negative = d < 0
        let x = abs(d)

        // Shortest round-trip digits + decimal exponent, taken from Swift's own
        // (Errol/Ryu-quality) description and re-rendered under ECMA's rules.
        let (digits, pointPos) = shortestDigits(x)
        let k = digits.count
        let n = pointPos

        var out: String
        if k <= n && n <= 21 {
            out = digits + String(repeating: "0", count: n - k)
        } else if 0 < n && n <= 21 {
            let i = digits.index(digits.startIndex, offsetBy: n)
            out = String(digits[..<i]) + "." + String(digits[i...])
        } else if -6 < n && n <= 0 {
            out = "0." + String(repeating: "0", count: -n) + digits
        } else {
            let e = n - 1
            let sign = e >= 0 ? "+" : "-"
            let mantissa = k == 1 ? digits
                : String(digits.first!) + "." + String(digits.dropFirst())
            out = mantissa + "e" + sign + String(abs(e))
        }
        return negative ? "-" + out : out
    }

    /// Decimal digits (no leading/trailing zeros) and the position of the decimal point
    /// relative to the start of those digits, i.e. `x == 0.digits * 10^pointPos`.
    private static func shortestDigits(_ x: Double) -> (digits: String, pointPos: Int) {
        // Swift's description is the shortest string that round-trips, which is exactly
        // the digit set ECMA-262 asks for. Only the presentation differs, so parse it back.
        let s = "\(x)"
        var mantissa = s
        var exp = 0
        if let eIdx = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = String(s[..<eIdx])
            exp = Int(s[s.index(after: eIdx)...]) ?? 0
        }
        var intPart = mantissa
        var fracPart = ""
        if let dot = mantissa.firstIndex(of: ".") {
            intPart = String(mantissa[..<dot])
            fracPart = String(mantissa[mantissa.index(after: dot)...])
        }
        var digits = intPart + fracPart
        var pointPos = intPart.count + exp

        // Strip leading zeros, each one shifting the point left.
        while digits.count > 1 && digits.first == "0" {
            digits.removeFirst()
            pointPos -= 1
        }
        // Strip trailing zeros; they do not move the point.
        while digits.count > 1 && digits.last == "0" {
            digits.removeLast()
        }
        if digits == "0" { return ("0", 1) }
        return (digits, pointPos)
    }

    /// `Number.prototype.toFixed(f)` - ECMA-262 21.1.3.3.
    ///
    /// Ties pick the LARGER n (toward +infinity), which is not what `String(format:)`
    /// does. `NutrientRow.fmt` and `SwapComparisonCard` both call this with f = 1.
    public static func toFixed(_ d: Double, _ f: Int) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
        if abs(d) >= 1e21 { return toString(d) }

        let negative = d < 0
        let x = abs(d)
        let scale = pow(10.0, Double(f))

        // "Let n be an integer for which n / 10^f - x is as close to zero as possible.
        //  If there are two such n, pick the larger n."
        var n = (x * scale).rounded(.toNearestOrAwayFromZero)
        // .toNearestOrAwayFromZero already picks the larger n for a positive x on a tie,
        // but re-derive on the exact boundary to avoid a scaling artefact.
        let lower = n - 1
        if abs(lower / scale - x) < abs(n / scale - x) { n = lower }

        var s: String
        if f == 0 {
            s = String(Int64(n))
        } else {
            let digits = String(Int64(n))
            let padded = digits.count <= f
                ? String(repeating: "0", count: f - digits.count + 1) + digits
                : digits
            let split = padded.index(padded.endIndex, offsetBy: -f)
            s = String(padded[..<split]) + "." + String(padded[split...])
        }
        // JS prints "-0.0" for a negative value that rounds to zero.
        return negative && n != 0 ? "-" + s : (negative ? "-" + s : s)
    }

    /// `value.toLocaleString('de-DE')` for the calorie badges: 2019 -> "2.019".
    public static func toLocaleStringDE(_ d: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 3
        return f.string(from: NSNumber(value: d)) ?? toString(d)
    }

    /// `parseFloat` - reads the longest valid numeric prefix, NaN when there is none.
    public static func parseFloat(_ s: String) -> Double {
        var seenDigit = false, seenDot = false, seenExp = false
        var end = s.startIndex
        var i = s.startIndex
        // optional sign
        if i < s.endIndex, s[i] == "+" || s[i] == "-" { i = s.index(after: i) }
        while i < s.endIndex {
            let c = s[i]
            if c.isASCII && c.isNumber {
                seenDigit = true
                end = s.index(after: i)
            } else if c == "." && !seenDot && !seenExp {
                seenDot = true
            } else if (c == "e" || c == "E") && seenDigit && !seenExp {
                // Only commit to the exponent if at least one digit follows it.
                var j = s.index(after: i)
                if j < s.endIndex, s[j] == "+" || s[j] == "-" { j = s.index(after: j) }
                guard j < s.endIndex, s[j].isASCII, s[j].isNumber else { break }
                seenExp = true
            } else {
                break
            }
            i = s.index(after: i)
        }
        guard seenDigit else { return .nan }
        return Double(s[s.startIndex..<end]) ?? .nan
    }
}

extension Comparable {
    @inlinable func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
