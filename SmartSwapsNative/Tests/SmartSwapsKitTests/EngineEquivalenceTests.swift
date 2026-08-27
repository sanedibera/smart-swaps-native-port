import XCTest
@testable import SmartSwapsKit

/// Differential equivalence against the live TypeScript engine.
///
/// Reference data is produced by Tools/dump-engine-reference.ts, which imports the real
/// modules from app/engine/ - not a reimplementation, which would drift.
/// Floats compare to 1e-9; everything else compares exactly.
final class EngineEquivalenceTests: XCTestCase {

    static let EPS = 1e-9

    struct Ref: Decodable {
        let strings: [S]
        let perFood: [PF]
        let pairs: [P]
        let swaps: [SW]
        let dishes: [D]
        let lines: [L]
        let indexStats: IX
        let parse: [PR]

        struct S: Decodable { let s: String; let n: String; let a: String }
        struct PF: Decodable {
            let id: String; let liq: Int; let rawIng: Int; let supp: String?
            let prod: Int; let pgroup: String?; let cfn: String
            let meat: Int; let animal: Int; let plant: Int
            let vgt: Int; let vgn: Int; let bal: Int
            let attrs: [Int]?
        }
        struct P: Decodable {
            let a: String; let b: String
            let cos: Double?; let ev: Double
            let f: [Double?]; let p: Double
            let veto: String?; let vetoSweet: String?
        }
        struct SW: Decodable { let id: String; let d: Int; let top: [T]
            struct T: Decodable { let c: String; let s: Double } }
        struct D: Decodable { let ids: [String]; let flavour: String }
        struct L: Decodable {
            let l: String; let ok: String; let brand: String?; let exact: String?
            let knm: Int; let ger: String
        }
        struct IX: Decodable { let index: Int; let stem: Int; let shingle: Int; let fourGram: Int }
        struct PR: Decodable {
            let l: String
            let p: PInner?
            let mf: String?; let mc: Double?; let mh: Int?
            struct PInner: Decodable { let f: String?; let c: Double }
        }
    }

    static let ref: Ref = {
        try! JSONDecoder().decode(Ref.self, from: Fixtures.data("engine-reference.json"))
    }()

    static let foods: [FoodItem] = {
        try! DatabaseService.shared.openReadOnlyForTests()
        return try! DatabaseService.shared.getAllFoods()
    }()

    static let byId: [String: FoodItem] = {
        Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
    }()

    private func assertClose(_ got: Double, _ want: Double, _ msg: @autoclosure () -> String) {
        if got == want { return }
        XCTAssertEqual(got, want, accuracy: Self.EPS, msg())
    }

    // MARK: - 1. normalize / asciiFold

    func testStringNormalisation() {
        var checked = 0
        for c in Self.ref.strings {
            XCTAssertEqual(EngineStrings.normalize(c.s), c.n, "normalize(\(c.s.debugDescription))")
            XCTAssertEqual(EngineStrings.asciiFold(c.s), c.a, "asciiFold(\(c.s.debugDescription))")
            checked += 1
        }
        print("strings: \(checked) inputs matched")
    }

    // MARK: - 2. Per-food predicates, all 7,140 foods

    func testPerFoodPredicates() {
        for r in Self.ref.perFood {
            guard let f = Self.byId[r.id] else { XCTFail("missing food \(r.id)"); continue }
            XCTAssertEqual(SwapAlgorithm.isLiquid(f) ? 1 : 0, r.liq, "isLiquid \(r.id) \(f.name)")
            XCTAssertEqual(SwapAlgorithm.isRawIngredient(f) ? 1 : 0, r.rawIng, "isRawIngredient \(r.id)")
            XCTAssertEqual(SwapAlgorithm.swapSuppressionReason(f)?.rawValue, r.supp, "suppression \(r.id)")
            XCTAssertEqual(ProduceGroups.isProduce(f) ? 1 : 0, r.prod, "isProduce \(r.id)")
            XCTAssertEqual(ProduceGroups.getProduceGroup(f), r.pgroup, "produceGroup \(r.id) \(f.name)")
            XCTAssertEqual(CulinaryFilter.getCulinaryFunction(f).rawValue, r.cfn, "culinaryFn \(r.id) \(f.name)")
            XCTAssertEqual(DietaryFilter.containsMeatOrFish(f) ? 1 : 0, r.meat, "meatOrFish \(r.id) \(f.name)")
            XCTAssertEqual(DietaryFilter.containsAnimalProduct(f) ? 1 : 0, r.animal, "animal \(r.id) \(f.name)")
            XCTAssertEqual(DietaryFilter.isPlantAlternative(f) ? 1 : 0, r.plant, "plantAlt \(r.id)")
            XCTAssertEqual(DietaryFilter.isAllowedForDiet(f, ["Vegetarian"]) ? 1 : 0, r.vgt, "vgt \(r.id)")
            XCTAssertEqual(DietaryFilter.isAllowedForDiet(f, ["Vegan"]) ? 1 : 0, r.vgn, "vgn \(r.id)")
            XCTAssertEqual(DietaryFilter.isAllowedForDiet(f, ["Balanced"]) ? 1 : 0, r.bal, "bal \(r.id)")

            let a = FoodAttributesStore.getAttributes(r.id)
            if let want = r.attrs {
                guard let a else { XCTFail("attrs missing \(r.id)"); continue }
                let got = a.sensory + [a.culinaryRole, a.prepState, a.glycemicLoad, a.satiety,
                                       a.caffeine ? 1 : 0, a.alcohol ? 1 : 0, a.timeOfDayMask]
                XCTAssertEqual(got, want, "attrs \(r.id)")
            } else {
                XCTAssertNil(a, "attrs should be nil \(r.id)")
            }
        }
        print("perFood: \(Self.ref.perFood.count) foods matched")
    }

    // MARK: - 3. Pairwise: cosine, evaluateSwap, GBM features + probability, veto

    func testPairwise() {
        for (i, r) in Self.ref.pairs.enumerated() {
            guard let a = Self.byId[r.a], let b = Self.byId[r.b] else { XCTFail("missing"); continue }

            let cos = FoodEmbeddings.embeddingCosine(a.id, b.id)
            if let want = r.cos {
                guard let cos else { XCTFail("cosine nil at \(i)"); continue }
                assertClose(cos, want, "cosine \(r.a)->\(r.b)")
            } else {
                XCTAssertNil(cos, "cosine should be nil at \(i)")
            }

            assertClose(SwapAlgorithm.evaluateSwap(a, b), r.ev, "evaluateSwap \(r.a)->\(r.b)")

            let lm = SwapAlgorithm.isLiquid(a) != SwapAlgorithm.isLiquid(b) ? 1 : 0
            let rm = SwapAlgorithm.isRawIngredient(a) != SwapAlgorithm.isRawIngredient(b) ? 1 : 0
            let feats = SwapGbm.extractGbmFeatures(source: a, candidate: b, cosineSim: cos,
                                                   liquidMismatch: lm, rawIngredientMismatch: rm)
            XCTAssertEqual(feats.count, r.f.count, "feature count at \(i)")
            for k in 0..<Swift.min(feats.count, r.f.count) {
                switch (feats[k], r.f[k]) {
                case let (g?, w?): assertClose(g, w, "feature[\(k)] \(SwapGbm.FEATURE_NAMES[k]) \(r.a)->\(r.b)")
                case (nil, nil): break
                default: XCTFail("feature[\(k)] \(SwapGbm.FEATURE_NAMES[k]) nil-ness differs at \(i): got \(String(describing: feats[k])) want \(String(describing: r.f[k]))")
                }
            }
            assertClose(SwapGbm.predictSwapQualityGbm(feats), r.p, "gbm \(r.a)->\(r.b)")

            XCTAssertEqual(CulinaryFilter.culinaryVeto(a, b, .SAVOURY), r.veto, "veto savoury \(r.a)->\(r.b)")
            XCTAssertEqual(CulinaryFilter.culinaryVeto(a, b, .SWEET), r.vetoSweet, "veto sweet \(r.a)->\(r.b)")
        }
        print("pairs: \(Self.ref.pairs.count) pairs matched")
    }

    // MARK: - 4. findBestSwaps end to end

    func testFindBestSwaps() {
        let diets: [[String]] = [["Balanced"], ["Vegetarian"], ["Vegan"]]
        for r in Self.ref.swaps {
            guard let f = Self.byId[r.id] else { XCTFail("missing \(r.id)"); continue }
            let got: [SwapAlgorithm.SwapResult]
            if r.d < 3 {
                got = SwapAlgorithm.findBestSwaps(f, Self.foods, 5, diets[r.d])
            } else {
                got = SwapAlgorithm.findBestSwaps(f, Self.foods, 5, ["Balanced"],
                    .init(minImprovement: 0, allowWholeFoods: true))
            }
            XCTAssertEqual(got.map(\.candidate.id), r.top.map(\.c),
                           "findBestSwaps ids for \(r.id) (\(f.name)) diet \(r.d)")
            for (k, t) in r.top.enumerated() where k < got.count {
                assertClose(got[k].score, t.s, "findBestSwaps score \(r.id)[\(k)]")
            }
        }
        print("swaps: \(Self.ref.swaps.count) slates matched")
    }

    // MARK: - 5. Dish flavour

    func testDishFlavour() {
        for d in Self.ref.dishes {
            let foods = d.ids.compactMap { Self.byId[$0] }
            XCTAssertEqual(CulinaryFilter.getDishFlavour(foods).rawValue, d.flavour)
        }
        print("dishes: \(Self.ref.dishes.count) matched")
    }

    // MARK: - 6. Dictionary tiers and key normalisation

    func testDictionaryTiers() {
        for r in Self.ref.lines {
            XCTAssertEqual(OverrideKey.normalizeOverrideKey(r.l), r.ok, "overrideKey \(r.l.debugDescription)")
            XCTAssertEqual(BrandDict.matchBrandDict(r.l), r.brand, "brandDict \(r.l.debugDescription)")
            XCTAssertEqual(ExactLookup.matchExactLookup(r.l), r.exact, "exactLookup \(r.l.debugDescription)")
            XCTAssertEqual(KnownNonMatches.isKnownNonMatch(r.l) ? 1 : 0, r.knm, "knownNonMatch \(r.l.debugDescription)")
        }
        print("lines: \(Self.ref.lines.count) matched")
    }
}

// MARK: - 7. The retrieval stage end to end

extension EngineEquivalenceTests {

    static let index: FoodIndexData = FoodIndex.buildFoodIndex(foods)

    func testIndexShape() {
        let ix = Self.index
        XCTAssertEqual(ix.index.count, Self.ref.indexStats.index, "index key count")
        XCTAssertEqual(ix.stemIndex.count, Self.ref.indexStats.stem, "stem key count")
        XCTAssertEqual(ix.shingleIndex.count, Self.ref.indexStats.shingle, "shingle key count")
        XCTAssertEqual(ix.fourGramIndex.count, Self.ref.indexStats.fourGram, "fourGram key count")
        print("index: \(ix.index.count)/\(ix.stemIndex.count)/\(ix.shingleIndex.count)/\(ix.fourGramIndex.count) matched")
    }

    func testGermanAbbreviations() {
        for r in Self.ref.lines {
            XCTAssertEqual(GermanAbbreviations.expandGermanAbbreviations(r.l), r.ger,
                           "expandGermanAbbreviations(\(r.l.debugDescription))")
        }
    }

    func testParseReceiptLine() {
        var checked = 0
        for r in Self.ref.parse {
            let m = ReceiptParser.matchFoodToOcrText(r.l, Self.foods, Self.index)
            XCTAssertEqual(m?.food.id, r.mf, "matchFoodToOcrText food for \(r.l.debugDescription)")
            if let want = r.mc, let m {
                assertClose(m.confidence, want, "matchFoodToOcrText confidence for \(r.l.debugDescription)")
            }
            if let want = r.mh { XCTAssertEqual(m.map { $0.hasStrongHit ? 1 : 0 }, want,
                                                "hasStrongHit for \(r.l.debugDescription)") }

            let p = ReceiptParser.parseReceiptLine(r.l, Self.foods, Self.index)
            if let want = r.p {
                XCTAssertNotNil(p, "parseReceiptLine should be non-nil for \(r.l.debugDescription)")
                XCTAssertEqual(p?.matchedFood?.id, want.f, "parseReceiptLine food for \(r.l.debugDescription)")
                if let p { assertClose(p.confidence, want.c, "parseReceiptLine confidence for \(r.l.debugDescription)") }
            } else {
                XCTAssertNil(p, "parseReceiptLine should be nil for \(r.l.debugDescription)")
            }
            checked += 1
        }
        print("parse: \(checked) lines matched")
    }
}
