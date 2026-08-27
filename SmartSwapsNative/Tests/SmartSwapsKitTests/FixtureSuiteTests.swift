import XCTest
@testable import SmartSwapsKit

/// The project's own regression suites, run against the Swift engine.
///
/// These are not new tests written for the port - they are the SAME cases the RN project
/// gates its own commits on, exported verbatim by Tools/export-fixtures.ts. The frozen
/// `baseline.snapshot.json` is copied through untouched and must be reproduced exactly.
final class FixtureSuiteTests: XCTestCase {

    static let foods: [FoodItem] = {
        try! DatabaseService.shared.openReadOnlyForTests()
        return try! DatabaseService.shared.getAllFoods()
    }()
    static let index: FoodIndexData = FoodIndex.buildFoodIndex(foods)
    static let byId: [String: FoodItem] = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
    static let byName: [String: FoodItem] = {
        var m: [String: FoodItem] = [:]
        // First wins, matching `new Map(foods.map(...))`? No - JS Map.set overwrites, so
        // the LAST food with a given lowercased name wins. Mirrored here.
        for f in foods { m[f.name.lowercased()] = f }
        return m
    }()

    /// Confidence floor below which the UI shows "Not Found". Mirrors ReceiptItemList.
    static let DISPLAY_CONFIDENCE_FLOOR = 0.45

    // MARK: - scripts/regression.test.ts

    struct RegressionCase: Decodable { let line: String; let expected: String?; let note: String? }

    func testRegressionSuite() throws {
        let cases = try JSONDecoder().decode([RegressionCase].self,
                                             from: Fixtures.data("regression-cases.json"))
        XCTAssertEqual(cases.count, 55)
        var failures: [String] = []
        for c in cases {
            let parsed = ReceiptParser.parseReceiptLine(c.line, Self.foods, Self.index)
            // A line "resolves" only if it produced a match the UI would display.
            let resolved: FoodItem? = {
                guard let parsed, let f = parsed.matchedFood,
                      parsed.confidence >= Self.DISPLAY_CONFIDENCE_FLOOR else { return nil }
                return f
            }()
            if resolved?.id != c.expected {
                failures.append("\"\(c.line)\" expected \(c.expected ?? "(no match)") "
                                + "got \(resolved?.id ?? "(no match)")"
                                + (c.note.map { "  [\($0)]" } ?? ""))
            }
        }
        XCTAssertTrue(failures.isEmpty, "regression failures:\n" + failures.joined(separator: "\n"))
        print("regression: \(cases.count - failures.count)/\(cases.count) passed")
    }

    // MARK: - scripts/baseline-eval.ts against the frozen snapshot

    struct BaselineCase: Decodable { let line: String; let expected: String?; let bucket: String }
    struct Snapshot: Decodable {
        let runAt: String
        let mode: String
        let totals: [Total]
        let cases: [Case]
        struct Total: Decodable {
            let bucket: String; let total: Int; let correct: Int
            let miss: Int; let wrong: Int; let accuracy: Double
        }
        struct Case: Decodable {
            let line: String; let bucket: String
            let expected: String?; let actual: String?; let outcome: String
        }
    }

    /// scripts/baseline-eval.ts, run offline (tiers 1-2), against the committed snapshot.
    /// The snapshot is regenerated whenever the engine changes (`npx tsx
    /// scripts/baseline-eval.ts --save scripts/baseline.snapshot.json`) - it is a frozen
    /// artefact of a specific engine revision, not a hand-authored spec, so it is only
    /// ever compared against the engine revision it was taken from.
    func testBaselineSnapshotReproducedExactly() throws {
        let cases = try JSONDecoder().decode([BaselineCase].self,
                                             from: Fixtures.data("baseline-cases.json"))
        let snap = try JSONDecoder().decode(Snapshot.self, from: Fixtures.data("baseline-snapshot.json"))
        XCTAssertEqual(snap.mode, "offline", "must be the offline run (tiers 1-4 only)")
        XCTAssertEqual(cases.count, snap.cases.count)

        let deps = ResolveProduct.Deps(allFoods: Self.foods, foodIndexData: Self.index)
        // The offline harness never calls OverrideStore.load(), which makes tier 1 inert.
        OverrideStore.shared.resetForTests()

        func grade(_ expected: String?, _ actual: String?) -> String {
            if actual == expected { return "correct" }
            if actual == nil { return "miss" }
            return "wrong"
        }

        var byBucket: [String: (total: Int, correct: Int, miss: Int, wrong: Int)] = [:]
        var mismatches: [String] = []

        for (i, c) in cases.enumerated() {
            let parsed = ResolveProduct.resolveProductLine(c.line, deps)
            let actual: String? = {
                guard let parsed, let f = parsed.matchedFood,
                      parsed.confidence >= Self.DISPLAY_CONFIDENCE_FLOOR else { return nil }
                return f.id
            }()
            let outcome = grade(c.expected, actual)

            let want = snap.cases[i]
            XCTAssertEqual(want.line, c.line, "case order drifted at \(i)")
            if actual != want.actual || outcome != want.outcome {
                mismatches.append("[\(c.bucket)] \"\(c.line)\" snapshot=\(want.actual ?? "null")/\(want.outcome) "
                                  + "got=\(actual ?? "null")/\(outcome)")
            }

            var b = byBucket[c.bucket] ?? (0, 0, 0, 0)
            b.total += 1
            switch outcome {
            case "correct": b.correct += 1
            case "miss": b.miss += 1
            default: b.wrong += 1
            }
            byBucket[c.bucket] = b
        }

        XCTAssertTrue(mismatches.isEmpty,
                      "baseline snapshot mismatches (\(mismatches.count)):\n"
                      + mismatches.prefix(25).joined(separator: "\n"))

        for t in snap.totals {
            let got = byBucket[t.bucket] ?? (0, 0, 0, 0)
            XCTAssertEqual(got.total, t.total, "\(t.bucket) total")
            XCTAssertEqual(got.correct, t.correct, "\(t.bucket) correct")
            XCTAssertEqual(got.miss, t.miss, "\(t.bucket) miss")
            XCTAssertEqual(got.wrong, t.wrong, "\(t.bucket) wrong")
            print("baseline \(t.bucket): \(got.correct)/\(got.total) correct, "
                  + "\(got.miss) miss, \(got.wrong) wrong (snapshot \(t.correct)/\(t.total))")
        }
    }

    // MARK: - scripts/culinary.test.ts

    struct CulinaryFixture: Decodable {
        let mustVeto: [Pair]
        let mustPass: [Pair]
        struct Pair: Decodable { let a: String; let b: String; let dish: String; let why: String }
    }

    func testCulinaryGate() throws {
        let fx = try JSONDecoder().decode(CulinaryFixture.self, from: Fixtures.data("culinary-cases.json"))
        XCTAssertGreaterThanOrEqual(fx.mustVeto.count, 19)
        XCTAssertGreaterThanOrEqual(fx.mustPass.count, 18)

        func food(_ n: String) throws -> FoodItem {
            guard let f = Self.byName[n.lowercased()] else {
                throw XCTSkip("no such food: \(n)")
            }
            return f
        }

        for p in fx.mustVeto {
            let flavour = CulinaryFilter.DishFlavour(rawValue: p.dish)!
            let reason = CulinaryFilter.culinaryVeto(try food(p.a), try food(p.b), flavour)
            XCTAssertNotNil(reason, "MUST VETO \(p.a) -> \(p.b)  [\(p.why)]")
        }
        for p in fx.mustPass {
            let flavour = CulinaryFilter.DishFlavour(rawValue: p.dish)!
            let reason = CulinaryFilter.culinaryVeto(try food(p.a), try food(p.b), flavour)
            XCTAssertNil(reason, "MUST PASS \(p.a) -> \(p.b)  [\(p.why)] but vetoed: \(reason ?? "")")
        }
        print("culinary: \(fx.mustVeto.count) veto + \(fx.mustPass.count) pass cases green")
    }
}
