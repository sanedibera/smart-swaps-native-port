import Foundation

/// Port of `app/services/database.ts`.
///
/// REPRODUCED FAITHFULLY, including the bit the source itself flags as a shortcut: the
/// bundled database is DELETED AND RE-COPIED on every launch ("For simplicity during
/// development, we'll overwrite it to ensure we have the latest version"). That is a real
/// behaviour of the app being ported - a user's database file never survives a restart -
/// so it is preserved rather than quietly improved. Recorded in PORTING_NOTES.md.
public final class DatabaseService {
    public static let shared = DatabaseService()

    private var db: SQLiteDB?
    private let lock = NSLock()

    private init() {}

    /// Where the working copy lives, mirroring expo-sqlite's `SQLite/` subdirectory.
    public static var workingCopyURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("SQLite").appendingPathComponent("smartswaps.db")
    }

    /// Bundled source database.
    public static var bundledURL: URL {
        guard let u = Bundle.module.url(forResource: "Resources/smartswaps.db", withExtension: nil)
                ?? Bundle.module.url(forResource: "smartswaps.db", withExtension: nil) else {
            fatalError("smartswaps.db missing from bundle")
        }
        return u
    }

    public func open() throws {
        lock.lock(); defer { lock.unlock() }
        if db != nil { return }
        let dst = Self.workingCopyURL
        let fm = FileManager.default
        // Delete-then-copy, exactly as initDatabase() does.
        if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
        try? fm.createDirectory(at: dst.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try fm.copyItem(at: Self.bundledURL, to: dst)
        db = try SQLiteDB(path: dst.path)
    }

    /// Opens the bundled file directly, skipping the copy. Tests only - the copy step is
    /// app behaviour, not read behaviour, and re-copying 7.6 MB per test is waste.
    public func openReadOnlyForTests() throws {
        lock.lock(); defer { lock.unlock() }
        if db != nil { return }
        db = try SQLiteDB(path: Self.bundledURL.path)
    }

    // Column order below is the physical order in the `foods` table, which is what
    // `SELECT *` yields. Verified against the schema.
    public func getAllFoods() throws -> [FoodItem] {
        guard let db else { fatalError("DatabaseService.open() not called") }
        var out: [FoodItem] = []
        out.reserveCapacity(7200)
        try db.query("SELECT * FROM foods") { r in
            var n = FoodNutrients()
            n.kcal = r.double(10)
            n.protein_g = r.double(11)
            n.carbs_g = r.double(12)
            n.sugars_g = r.double(13)
            n.fat_g = r.double(14)
            n.saturated_fat_g = r.double(15)
            n.fiber_g = r.double(16)
            n.salt_g = r.double(17)
            if let microsJSON = r.text(18),
               let d = microsJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                var dict: [String: Double] = [:]
                for (k, v) in obj { if let num = v as? NSNumber { dict[k] = num.doubleValue } }
                n.micros = Micros(json: dict)
            }
            out.append(FoodItem(
                id: r.text(0) ?? "",
                name: r.text(1) ?? "",
                name_de: r.text(2),
                category: r.text(3) ?? "",
                swiss_category: r.text(4) ?? "",
                health_score: r.double(5),
                nutri_grade: r.text(6),
                nova_group: r.int(7),
                swap_suggestion_id: r.text(8),
                icon_key: r.text(9),
                nutrients_per_100: n
            ))
        }
        return out
    }

    public func getIconLibrary() throws -> [String: String] {
        guard let db else { fatalError("DatabaseService.open() not called") }
        var library: [String: String] = [:]
        try db.query("SELECT icon_key, svg_content FROM icon_library") { r in
            if let k = r.text(0), let v = r.text(1) { library[k] = v }
        }
        return library
    }

    /// Recipes plus their ingredients, grouped in memory from ONE ordered query - not a
    /// JOIN and not N+1, both of which would change ingredient order.
    public func getAllRecipes() throws -> [RecipeRaw] {
        guard let db else { fatalError("DatabaseService.open() not called") }

        var ingredientsByRecipe = OrderedDictionary<String, [RecipeIngredientRaw]>()
        try db.query("SELECT * FROM recipe_ingredients ORDER BY recipe_id, sort_order") { r in
            let rid = r.text(0) ?? ""
            var list = ingredientsByRecipe[rid] ?? []
            list.append(RecipeIngredientRaw(
                food_id: r.text(1),
                raw_text: r.text(2) ?? "",
                grams: r.doubleOrNil(3),
                kcal: r.doubleOrNil(4)
            ))
            ingredientsByRecipe[rid] = list
        }

        var out: [RecipeRaw] = []
        try db.query("SELECT * FROM recipes") { r in
            let id = r.text(0) ?? ""
            var steps: [String] = []
            if let s = r.text(7), let d = s.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: d) as? [Any] {
                steps = arr.compactMap { $0 as? String }
            }
            out.append(RecipeRaw(
                id: id,
                name: r.text(1) ?? "",
                url: r.text(2) ?? "",
                image: r.text(3),
                serves: r.int(4) ?? 0,
                subcategory: r.text(5) ?? "",
                dish_type: r.text(6) ?? "",
                steps: steps,
                ingredients: ingredientsByRecipe[id] ?? []
            ))
        }
        return out
    }
}

public struct RecipeIngredientRaw {
    public let food_id: String?
    public let raw_text: String
    public let grams: Double?
    public let kcal: Double?
}

public struct RecipeRaw {
    public let id: String
    public let name: String
    public let url: String
    public let image: String?
    public let serves: Int
    public let subcategory: String
    public let dish_type: String
    public let steps: [String]
    public let ingredients: [RecipeIngredientRaw]
}
