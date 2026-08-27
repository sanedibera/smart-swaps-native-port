import Foundation

/// `Array.prototype.sort` as V8 implements it: TimSort, with galloping merges.
///
/// WHY NOT JUST A STABLE SORT. For a comparator that defines a total order, any stable
/// sort gives the same answer and this file would be unnecessary. One comparator in this
/// engine is NOT a total order - `matchFoodToOcrText`'s:
///
///     if (Math.abs(b.confidence - a.confidence) <= 0.03) return a.unmatchedCount - b.unmatchedCount;
///     return b.confidence - a.confidence;
///
/// Inside the 0.03 band it switches sort key, so it is not transitive: it can report
/// a<b, b<c and c<a. The output is therefore a property of the algorithm - which
/// comparisons it performs, in which order - not of the comparator alone. Reproducing
/// the app's chosen match means reproducing V8's sort, not merely a stable one.
///
/// This is the classic TimSort of Python's listsort / Java's java.util.TimSort, which is
/// what V8's Torque implementation was ported from, including the corrected
/// merge-collapse invariant.
public enum JSSort {

    /// Comparators return a Double, exactly as JS ones do. Sign is what matters;
    /// NaN and -0 are treated as 0, per ECMA-262 SortCompare.
    public typealias Comparator<T> = (T, T) -> Double

    /// `array.sort(comparator)`, returning a new array.
    public static func sorted<T>(_ input: [T], _ compare: @escaping Comparator<T>) -> [T] {
        var a = input
        sort(&a, compare)
        return a
    }

    /// In-place `array.sort(comparator)`.
    public static func sort<T>(_ a: inout [T], _ compare: @escaping Comparator<T>) {
        var s = TimSort(compare)
        s.sort(&a)
    }

    /// ECMA-262 SortCompare: coerce the comparator result to an ordering.
    /// `undefined`/`NaN` are treated as 0, and so is -0.
    @inlinable
    public static func order(_ v: Double) -> Int {
        if v.isNaN { return 0 }
        if v < 0 { return -1 }
        if v > 0 { return 1 }
        return 0
    }
}

private struct TimSort<T> {
    private let compare: JSSort.Comparator<T>
    /// V8's kMinGallopWins.
    private static var minGallopInit: Int { 7 }
    private var minGallop = 7
    private var runBase: [Int] = []
    private var runLen: [Int] = []
    private var tmp: [T] = []

    init(_ compare: @escaping JSSort.Comparator<T>) { self.compare = compare }

    @inline(__always)
    private func cmp(_ x: T, _ y: T) -> Int { JSSort.order(compare(x, y)) }

    mutating func sort(_ a: inout [T]) {
        let n = a.count
        if n < 2 { return }
        minGallop = TimSort.minGallopInit
        runBase.removeAll(); runLen.removeAll()

        // MEASURED: V8 skips run detection entirely below 8 elements and binary-insertion
        // sorts the whole array. Verified by counting comparator calls on a descending
        // input - n=7 costs 14 calls (binary insertion) while n=8 costs 7 (one detected
        // descending run, then reversed). Getting this wrong changes the result for an
        // inconsistent comparator: the n=7 case that first exposed it had my run detector
        // swallowing three elements into a "descending" run that V8 never formed.
        if n < 8 {
            binaryInsertionSort(&a, 0, 0, n)
            return
        }

        let minRun = TimSort.minRunLength(n)
        var low = 0
        var remaining = n
        while remaining != 0 {
            var currentRunLength = countAndMakeRun(&a, low, low + remaining)
            if currentRunLength < minRun {
                let forced = Swift.min(minRun, remaining)
                binaryInsertionSort(&a, low, low + currentRunLength, low + forced)
                currentRunLength = forced
            }
            runBase.append(low); runLen.append(currentRunLength)
            mergeCollapse(&a)
            low += currentRunLength
            remaining -= currentRunLength
        }
        mergeForceCollapse(&a)
    }

    /// Python/V8 `ComputeMinRunLength`: shift until < 64, adding 1 if any bit was dropped.
    static func minRunLength(_ nArg: Int) -> Int {
        var n = nArg
        var r = 0
        while n >= 64 {
            r |= n & 1
            n >>= 1
        }
        return n + r
    }

    /// Finds the run starting at `low`; reverses it in place if it is strictly descending.
    private func countAndMakeRun(_ a: inout [T], _ lowArg: Int, _ high: Int) -> Int {
        let low = lowArg + 1
        if low == high { return 1 }
        var runLength = 2
        let elementLow = a[low]
        let elementLowPred = a[low - 1]
        var order = cmp(elementLow, elementLowPred)
        let isDescending = order < 0
        var previousElement = elementLow
        var idx = low + 1
        while idx < high {
            let currentElement = a[idx]
            order = cmp(currentElement, previousElement)
            if isDescending {
                if order >= 0 { break }
            } else {
                if order < 0 { break }
            }
            previousElement = currentElement
            runLength += 1
            idx += 1
        }
        if isDescending {
            a[lowArg..<(lowArg + runLength)].reverse()
        }
        return runLength
    }

    /// Stable binary insertion sort of `[low, high)`, given `[low, start)` already sorted.
    private func binaryInsertionSort(_ a: inout [T], _ low: Int, _ startArg: Int, _ high: Int) {
        var start = (low == startArg) ? startArg + 1 : startArg
        while start < high {
            var left = low
            var right = start
            let pivot = a[right]
            while left < right {
                let mid = left + ((right - left) >> 1)
                if cmp(pivot, a[mid]) < 0 { right = mid } else { left = mid + 1 }
            }
            var p = start
            while p > left {
                a[p] = a[p - 1]
                p -= 1
            }
            a[left] = pivot
            start += 1
        }
    }

    private mutating func mergeCollapse(_ a: inout [T]) {
        while runLen.count > 1 {
            var n = runLen.count - 2
            if n > 0 && runLen[n - 1] <= runLen[n] + runLen[n + 1] {
                if runLen[n - 1] < runLen[n + 1] { n -= 1 }
                mergeAt(&a, n)
            } else if runLen[n] <= runLen[n + 1] {
                mergeAt(&a, n)
            } else {
                break
            }
        }
    }

    private mutating func mergeForceCollapse(_ a: inout [T]) {
        while runLen.count > 1 {
            var n = runLen.count - 2
            if n > 0 && runLen[n - 1] < runLen[n + 1] { n -= 1 }
            mergeAt(&a, n)
        }
    }

    private mutating func mergeAt(_ a: inout [T], _ i: Int) {
        var base1 = runBase[i],  len1 = runLen[i]
        let base2 = runBase[i + 1], len2Start = runLen[i + 1]
        var len2 = len2Start

        runLen[i] = len1 + len2
        runBase.remove(at: i + 1)
        runLen.remove(at: i + 1)

        // Skip the prefix of run1 that is already in place.
        let k = gallopRight(a, a[base2], base1, len1, 0)
        base1 += k
        len1 -= k
        if len1 == 0 { return }

        // Skip the suffix of run2 that is already in place.
        len2 = gallopLeft(a, a[base1 + len1 - 1], base2, len2, len2 - 1)
        if len2 == 0 { return }

        if len1 <= len2 {
            mergeLow(&a, base1, len1, base2, len2)
        } else {
            mergeHigh(&a, base1, len1, base2, len2)
        }
    }

    /// Leftmost position at which `key` could be inserted into the sorted run at `base`.
    private func gallopLeft(_ a: [T], _ key: T, _ base: Int, _ len: Int, _ hint: Int) -> Int {
        var lastOfs = 0
        var ofs = 1
        if cmp(key, a[base + hint]) > 0 {
            let maxOfs = len - hint
            while ofs < maxOfs && cmp(key, a[base + hint + ofs]) > 0 {
                lastOfs = ofs
                ofs = (ofs << 1) + 1
                if ofs <= 0 { ofs = maxOfs }
            }
            if ofs > maxOfs { ofs = maxOfs }
            lastOfs += hint
            ofs += hint
        } else {
            let maxOfs = hint + 1
            while ofs < maxOfs && cmp(key, a[base + hint - ofs]) <= 0 {
                lastOfs = ofs
                ofs = (ofs << 1) + 1
                if ofs <= 0 { ofs = maxOfs }
            }
            if ofs > maxOfs { ofs = maxOfs }
            let t = lastOfs
            lastOfs = hint - ofs
            ofs = hint - t
        }
        lastOfs += 1
        while lastOfs < ofs {
            let m = lastOfs + ((ofs - lastOfs) >> 1)
            if cmp(key, a[base + m]) > 0 { lastOfs = m + 1 } else { ofs = m }
        }
        return ofs
    }

    /// Rightmost position at which `key` could be inserted into the sorted run at `base`.
    private func gallopRight(_ a: [T], _ key: T, _ base: Int, _ len: Int, _ hint: Int) -> Int {
        var ofs = 1
        var lastOfs = 0
        if cmp(key, a[base + hint]) < 0 {
            let maxOfs = hint + 1
            while ofs < maxOfs && cmp(key, a[base + hint - ofs]) < 0 {
                lastOfs = ofs
                ofs = (ofs << 1) + 1
                if ofs <= 0 { ofs = maxOfs }
            }
            if ofs > maxOfs { ofs = maxOfs }
            let t = lastOfs
            lastOfs = hint - ofs
            ofs = hint - t
        } else {
            let maxOfs = len - hint
            while ofs < maxOfs && cmp(key, a[base + hint + ofs]) >= 0 {
                lastOfs = ofs
                ofs = (ofs << 1) + 1
                if ofs <= 0 { ofs = maxOfs }
            }
            if ofs > maxOfs { ofs = maxOfs }
            lastOfs += hint
            ofs += hint
        }
        lastOfs += 1
        while lastOfs < ofs {
            let m = lastOfs + ((ofs - lastOfs) >> 1)
            if cmp(key, a[base + m]) < 0 { ofs = m } else { lastOfs = m + 1 }
        }
        return ofs
    }

    private mutating func mergeLow(_ a: inout [T], _ base1: Int, _ len1Arg: Int, _ base2: Int, _ len2Arg: Int) {
        var len1 = len1Arg, len2 = len2Arg
        tmp = Array(a[base1..<(base1 + len1)])
        var cursor1 = 0
        var cursor2 = base2
        var dest = base1

        a[dest] = a[cursor2]; dest += 1; cursor2 += 1; len2 -= 1
        if len2 == 0 {
            for k in 0..<len1 { a[dest + k] = tmp[cursor1 + k] }
            return
        }
        if len1 == 1 {
            for k in 0..<len2 { a[dest + k] = a[cursor2 + k] }
            a[dest + len2] = tmp[cursor1]
            return
        }

        var gallop = minGallop
        outer: while true {
            var count1 = 0, count2 = 0
            repeat {
                if cmp(a[cursor2], tmp[cursor1]) < 0 {
                    a[dest] = a[cursor2]; dest += 1; cursor2 += 1
                    count2 += 1; count1 = 0
                    len2 -= 1
                    if len2 == 0 { break outer }
                } else {
                    a[dest] = tmp[cursor1]; dest += 1; cursor1 += 1
                    count1 += 1; count2 = 0
                    len1 -= 1
                    if len1 == 1 { break outer }
                }
            } while (count1 | count2) < gallop

            repeat {
                count1 = gallopRight(tmp, a[cursor2], cursor1, len1, 0)
                if count1 != 0 {
                    for k in 0..<count1 { a[dest + k] = tmp[cursor1 + k] }
                    dest += count1; cursor1 += count1; len1 -= count1
                    if len1 <= 1 { break outer }
                }
                a[dest] = a[cursor2]; dest += 1; cursor2 += 1
                len2 -= 1
                if len2 == 0 { break outer }

                count2 = gallopLeft(a, tmp[cursor1], cursor2, len2, 0)
                if count2 != 0 {
                    for k in 0..<count2 { a[dest + k] = a[cursor2 + k] }
                    dest += count2; cursor2 += count2; len2 -= count2
                    if len2 == 0 { break outer }
                }
                a[dest] = tmp[cursor1]; dest += 1; cursor1 += 1
                len1 -= 1
                if len1 == 1 { break outer }
                gallop -= 1
            } while count1 >= 7 || count2 >= 7
            if gallop < 0 { gallop = 0 }
            gallop += 2
        }
        minGallop = gallop < 1 ? 1 : gallop

        if len1 == 1 {
            for k in 0..<len2 { a[dest + k] = a[cursor2 + k] }
            a[dest + len2] = tmp[cursor1]
        } else {
            for k in 0..<len1 { a[dest + k] = tmp[cursor1 + k] }
        }
    }

    private mutating func mergeHigh(_ a: inout [T], _ base1: Int, _ len1Arg: Int, _ base2: Int, _ len2Arg: Int) {
        var len1 = len1Arg, len2 = len2Arg
        tmp = Array(a[base2..<(base2 + len2)])
        var cursor1 = base1 + len1 - 1
        var cursor2 = len2 - 1
        var dest = base2 + len2 - 1

        a[dest] = a[cursor1]; dest -= 1; cursor1 -= 1; len1 -= 1
        if len1 == 0 {
            for k in 0..<len2 { a[dest - (len2 - 1) + k] = tmp[k] }
            return
        }
        if len2 == 1 {
            dest -= len1; cursor1 -= len1
            for k in 1...len1 { a[dest + k] = a[cursor1 + k] }
            a[dest] = tmp[cursor2]
            return
        }

        var gallop = minGallop
        outer: while true {
            var count1 = 0, count2 = 0
            repeat {
                if cmp(tmp[cursor2], a[cursor1]) < 0 {
                    a[dest] = a[cursor1]; dest -= 1; cursor1 -= 1
                    count1 += 1; count2 = 0
                    len1 -= 1
                    if len1 == 0 { break outer }
                } else {
                    a[dest] = tmp[cursor2]; dest -= 1; cursor2 -= 1
                    count2 += 1; count1 = 0
                    len2 -= 1
                    if len2 == 1 { break outer }
                }
            } while (count1 | count2) < gallop

            repeat {
                count1 = len1 - gallopRight(a, tmp[cursor2], base1, len1, len1 - 1)
                if count1 != 0 {
                    dest -= count1; cursor1 -= count1; len1 -= count1
                    for k in stride(from: count1 - 1, through: 0, by: -1) { a[dest + 1 + k] = a[cursor1 + 1 + k] }
                    if len1 == 0 { break outer }
                }
                a[dest] = tmp[cursor2]; dest -= 1; cursor2 -= 1
                len2 -= 1
                if len2 == 1 { break outer }

                count2 = len2 - gallopLeft(tmp, a[cursor1], 0, len2, len2 - 1)
                if count2 != 0 {
                    dest -= count2; cursor2 -= count2; len2 -= count2
                    for k in 0..<count2 { a[dest + 1 + k] = tmp[cursor2 + 1 + k] }
                    if len2 <= 1 { break outer }
                }
                a[dest] = a[cursor1]; dest -= 1; cursor1 -= 1
                len1 -= 1
                if len1 == 0 { break outer }
                gallop -= 1
            } while count1 >= 7 || count2 >= 7
            if gallop < 0 { gallop = 0 }
            gallop += 2
        }
        minGallop = gallop < 1 ? 1 : gallop

        if len2 == 1 {
            dest -= len1; cursor1 -= len1
            for k in stride(from: len1, through: 1, by: -1) { a[dest + k] = a[cursor1 + k] }
            a[dest] = tmp[cursor2]
        } else {
            for k in 0..<len2 { a[dest - (len2 - 1) + k] = tmp[k] }
        }
    }
}

public extension Array {
    /// `this.sort(comparator)` with JS semantics. Non-mutating.
    func jsSorted(_ compare: @escaping JSSort.Comparator<Element>) -> [Element] {
        JSSort.sorted(self, compare)
    }
}

/// Test seam: `minRunLength` is on a private generic type, so expose the pure function.
public enum TimSortProbe {
    public static func minRunLength(_ n: Int) -> Int {
        var n = n, r = 0
        while n >= 64 { r |= n & 1; n >>= 1 }
        return n + r
    }
}
