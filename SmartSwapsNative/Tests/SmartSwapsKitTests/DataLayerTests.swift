import XCTest
@testable import SmartSwapsKit

/// Row-for-row diff of the Swift data layer against the TS one.
///
/// Order is asserted, not just contents: `SELECT * FROM foods` has no ORDER BY, and that
/// order propagates into filter order, sort tie-breaks and candidate insertion order all
/// through the engine.
final class DataLayerTests: XCTestCase {

    struct Ref: Decodable {
        let count: Int
        let rows: [Row]
        struct Row: Decodable {
            let i: String; let n: String; let d: String?; let c: String; let s: String
            let h: Double; let g: String?; let v: Int?; let k: String?
            // NULLABLE ON PURPOSE. 83 macro cells in the database are NULL
            // (protein_g 23, saturated_fat_g 23, fiber_g 27, fat_g 10), and nova_group is
            // NULL for all 7,140 rows. TS carries those through as `null`.
            //
            // Representing them as 0 in Swift is behaviourally identical HERE, and that
            // was checked rather than assumed: JS coerces null to 0 in arithmetic
            // (null - 3 === -3) and in relational comparison (null <= 20 is true), `||`
            // treats null and 0 alike, and nothing in the app compares a nutrient with
            // == / === - the only operators that would tell them apart. Verified by grep
            // across app/, components/ and SearchScreen.tsx.
            let u: [Double?]; let m: [Double?]
        }
    }

    override class func setUp() {
        super.setUp()
        try! DatabaseService.shared.openReadOnlyForTests()
    }

    static var foods: [FoodItem] = {
        try! DatabaseService.shared.openReadOnlyForTests()
        return try! DatabaseService.shared.getAllFoods()
    }()

    func testFoodsMatchTypeScriptExactly() throws {
        let ref = try JSONDecoder().decode(Ref.self, from: Fixtures.data("foods-reference.json"))
        let foods = Self.foods
        XCTAssertEqual(foods.count, ref.count)

        for (idx, r) in ref.rows.enumerated() {
            let f = foods[idx]
            XCTAssertEqual(f.id, r.i, "row \(idx): id (order mismatch)")
            XCTAssertEqual(f.name, r.n, "row \(idx) \(r.i): name")
            XCTAssertEqual(f.name_de, r.d, "row \(idx) \(r.i): name_de")
            XCTAssertEqual(f.category, r.c, "row \(idx) \(r.i): category")
            XCTAssertEqual(f.swiss_category, r.s, "row \(idx) \(r.i): swiss_category")
            XCTAssertEqual(f.health_score, r.h, "row \(idx) \(r.i): health_score")
            XCTAssertEqual(f.nutri_grade, r.g, "row \(idx) \(r.i): nutri_grade")
            XCTAssertEqual(f.nova_group, r.v, "row \(idx) \(r.i): nova_group")
            XCTAssertEqual(f.icon_key, r.k, "row \(idx) \(r.i): icon_key")

            let n = f.nutrients_per_100
            let u = [n.kcal, n.protein_g, n.carbs_g, n.sugars_g,
                     n.fat_g, n.saturated_fat_g, n.fiber_g, n.salt_g]
            XCTAssertEqual(u, r.u.map { $0 ?? 0 }, "row \(idx) \(r.i): macros")

            let m = Micros.keysInDeclarationOrder.map { n.micros[$0] }
            XCTAssertEqual(m, r.m.map { $0 ?? 0 }, "row \(idx) \(r.i): micros")
        }
    }

    func testIconLibraryLoads() throws {
        let lib = try DatabaseService.shared.getIconLibrary()
        XCTAssertEqual(lib.count, 85)
        for (_, svg) in lib { XCTAssertTrue(svg.contains("<svg")) }
    }

    func testRecipesLoadWithOrderedIngredients() throws {
        let recipes = try DatabaseService.shared.getAllRecipes()
        XCTAssertEqual(recipes.count, 955)
        XCTAssertEqual(recipes.reduce(0) { $0 + $1.ingredients.count }, 8571)
        XCTAssertTrue(recipes.contains { !$0.steps.isEmpty }, "steps JSON column must parse")
    }
}
