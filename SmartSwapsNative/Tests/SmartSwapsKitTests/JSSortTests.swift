import XCTest
@testable import SmartSwapsKit

/// Differential test of the TimSort port against V8's actual output.
///
/// Two of the three comparator shapes here are the real ones from the engine, and the
/// first is NOT a total order - so this is checking that the ALGORITHM matches, not just
/// that the sort is stable. Reference data comes from Tools/dump-sort-reference.mjs run
/// under node, i.e. from V8 itself.
final class JSSortTests: XCTestCase {

    struct Case: Decodable {
        let kind: String
        let items: [Item]
        let expected: [Int]
        struct Item: Decodable {
            let id: Int
            let confidence: Double?
            let unmatchedCount: Int?
            let score: Double?
            let hand: Int?
            let len: Int?
        }
    }
    struct Reference: Decodable { let cases: [Case] }

    func testMatchesV8() throws {
        let url = Fixtures.url("sort-reference.json")
        let ref = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(ref.cases.count, 400)

        var checked = 0
        for (i, c) in ref.cases.enumerated() {
            let got: [Int]
            switch c.kind {
            case "receiptBand":
                // matchFoodToOcrText's comparator, verbatim.
                got = JSSort.sorted(c.items) { a, b in
                    if abs(b.confidence! - a.confidence!) <= 0.03 {
                        return Double(a.unmatchedCount! - b.unmatchedCount!)
                    }
                    return b.confidence! - a.confidence!
                }.map(\.id)
            case "swapRank":
                // findBestSwaps' comparator, including JS `||` fall-through on a 0 or NaN.
                got = JSSort.sorted(c.items) { a, b in
                    JSNumber.or(b.score! - a.score!, Double(b.hand! - a.hand!))
                }.map(\.id)
            case "byLength":
                got = JSSort.sorted(c.items) { a, b in Double(b.len! - a.len!) }.map(\.id)
            default:
                XCTFail("unknown kind \(c.kind)"); continue
            }
            XCTAssertEqual(got, c.expected, "case \(i) (\(c.kind), n=\(c.items.count))")
            checked += 1
        }
        print("JSSort: \(checked) cases matched V8 exactly")
    }

    func testMinRunLength() {
        // Spot-check the Python/V8 ComputeMinRunLength shift-and-carry.
        XCTAssertEqual(TimSortProbe.minRunLength(63), 63)
        XCTAssertEqual(TimSortProbe.minRunLength(64), 32)
        XCTAssertEqual(TimSortProbe.minRunLength(65), 33)
        XCTAssertEqual(TimSortProbe.minRunLength(128), 32)
        XCTAssertEqual(TimSortProbe.minRunLength(129), 33)
        XCTAssertEqual(TimSortProbe.minRunLength(2000), 63)
    }
}
