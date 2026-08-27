# PORTING_INVENTORY.md — Phase 0

Inventory of the Expo SDK 54 / RN 0.81 app `smart-swaps-mobile` and its 1:1 mapping onto a
native Swift + SwiftUI target. Produced by reading every file in `app/`, `components/`,
`styles.ts`, `SearchScreen.tsx`, `modules/native-ocr/`, the bundled SQLite schema, and the
`scripts/` fixtures that Phase 3 must reproduce.

**Nothing has been written in Swift yet.** Sections marked **⚠ FLAG** need your decision or
acknowledgement before Phase 1.

Measured totals: 14,293 lines of TS/TSX across 66 source files; 7,140 foods, 955 recipes,
8,571 recipe ingredients, 85 icons in `assets/smartswaps.db` (7.6 MB); 4.15 MB of `.data.json`
model/embedding assets.

---

## 0. Target project layout

The RN project is untouched. Everything Swift lives under `SmartSwapsNative/`.

```
SmartSwapsNative/
  SmartSwaps.xcodeproj                  iOS app target, deployment target 16.4
  SmartSwaps/
    App/               SmartSwapsApp.swift, RootView.swift, TabBar, Router
    DesignSystem/      Colors.swift, GlobalStyles.swift, Typography.swift, JSNumber.swift
    Models/            FoodItem, Recipe, ScanRecord, ParsedReceiptItem …
    Data/              DatabaseService, StorageService, OverrideStore, MatchLog, OffClient
    State/             ProfileStore, FavoritesStore, SettingsStore, InventoryStore
    Engine/            pure Swift, no UIKit/SwiftUI import anywhere
    Components/        one file per components/*.tsx, same names
    Screens/           one file per route
    Resources/         smartswaps.db, *.data.json, *.json, Nunito fonts, OpenMoji assets
  SmartSwapsTests/     engine equivalence suite (Phase 3 gate)
  Tools/               TS harness that dumps reference JSON from the live TS engine
```

SPM only. Planned dependencies: **GRDB.swift** (SQLite) and one SVG renderer (§7.3). No
third-party UI framework.

---

## 1. Design tokens — `styles.ts` (178 ln)

| Source | Target |
|---|---|
| `COLORS` (42 entries) | `DesignSystem/Colors.swift` — `enum Colors`, exact hex, no `Color` asset catalog indirection |
| `globalStyles` (15 entries) | `DesignSystem/GlobalStyles.swift` — `ViewModifier`s |

`app.json` says `"userInterfaceStyle": "light"` and every screen hardcodes light colours, so
the Swift app pins `.preferredColorScheme(.light)`. No dark palette is derived.

Exact values that must survive: `globalStyles.card` = bg `#FFFFFF`, radius 24, padding 20,
marginBottom 16, shadow `#0F1D11` offset (0,6) opacity 0.04 radius 12. `scrollContent` =
paddingHorizontal 20 / paddingBottom 100 / paddingTop 10. `title` 32/800/-0.5,
`sectionTitle` 20/700/marginVertical 14, `subtitle` 14/lineHeight 20/marginTop 4,
`bodyText` 14/lineHeight 20. `primaryButton` paddingVertical 14, radius 14, marginTop 12.

Screens also use ~20 one-off colours never added to `COLORS` — the shopping-list blue family
(`#F0FAFF` `#D0EFFF` `#BFE7FF` `#0084C9` `#005480` `#006599` `#F0F8FF` `#B3E0FF`), the amber
`#F5A623`/`#FFF8E1`/`#FFEBEE` score family in `SearchScreen`/`food/[id]`, `#F59E0B` in
`NutrientRow`, the RecipeCard subcategory palette (`#FEF3C7` `#D97706` `#FFF3E0` `#F57C00`
`#EDE7F6` `#6D28D9` `#FCE4EC` `#C2185B` `#F9A825`), and `#F7F9F7` / `#F9FAF9` / `#FAFAFA`
screen backgrounds. These go into `Colors.Local` verbatim, not normalised into the palette.

**⚠ FLAG — fonts.** `(tabs)/_layout.tsx` sets `tabBarLabelStyle.fontFamily: "Nunito_500Medium"`,
but `expo-font` is listed as a plugin and **no font file is bundled and no font is loaded
anywhere in the source**. There is no `assets/fonts/`, no `useFonts()` call, no
`expo-google-fonts` dependency in `package.json`. So on the real device that string resolves
to nothing and the tab bar renders in **San Francisco**, as does every other text node in the
app (no other `fontFamily` appears anywhere). The brief instructs me to bundle Nunito — doing
so would be a *visible* deviation from the running app. **Default: use SF Pro everywhere,
matching observed behaviour.** Say the word if you want Nunito bundled instead.

---

## 2. Types — `app/types.ts` (94 ln)

| TS | Swift | Notes |
|---|---|---|
| `FoodNutrients` | `struct FoodNutrients: Codable` | 8 macros + `micros` |
| `FoodNutrients.micros` | `struct Micros: Codable` | 21 fixed keys, all `Double` |
| `FoodItem` | `struct FoodItem` | ⚠ reference semantics — see §5.2 |
| `RecipeIngredientRaw` / `RecipeRaw` | `struct` | DB row shapes |
| `RecipeIngredient` / `Recipe` | `struct` | hydrated shapes |

`nova_group`, `swap_suggestion_id`, `icon_key` are optional and their `nil`-ness is
load-bearing (`smartSwaps.findSmartSwap` branches on `nova_group === 4` / `=== 1`).
`micros` is `{}` when the DB column is null — modelled as all-zero, matching
`scaleNutrients`'s `?? 0` reads, but `food/[id].tsx` skips micro rows whose value is
`undefined || null || 0`, so an absent micros object and a zeroed one render identically.

---

## 3. Persistence

### 3.1 Keys (all preserved verbatim, JSON shape unchanged)

| Key | Owner | Swift |
|---|---|---|
| `@smart_swaps_profile` | `ProfileContext` | `ProfileStore` |
| `@smart_swaps_favorites` | `FavoritesContext` | `FavoritesStore` |
| `@smart_swaps_settings` | `SettingsContext` | `SettingsStore` |
| `@smart_swaps_scans` | `services/storage.ts` | `StorageService` |
| `@smart_swaps_interactions` | `services/storage.ts` | `StorageService` |
| `@smart_swaps_overrides` | `services/overrideStore.ts` | `OverrideStore` |
| `swap_personal_preferences_v1` | `engine/personalSwapPreferences.ts` | `PersonalSwapPreferences` |
| `swap_training_log_v1` | `engine/swapTrainingLog.ts` | `SwapTrainingLog`, cap `MAX_ROWS = 2000`, `slice(-MAX)` |
| `match_diagnostic_log_v1` | `services/matchLog.ts` | `MatchLog`, cap `MAX_ROWS = 500`, `slice(-MAX)` |

AsyncStorage on iOS is a plain key→string store, so the Swift replacement is a JSON-string
store keyed identically (`UserDefaults` for the small ones, a JSON file for `@smart_swaps_scans`
which can grow large). Both persist strings, so a value written by either app is readable by
the other — useful for the Phase 7 side-by-side.

`StorageService.saveScan` prepends (`[newScan, ...existing]`), initialises
`interactions: []` from an `Omit<ScanRecord,'interactions'>`, and every method swallows its
error (`console.error`, never throws). All three behaviours are ported as-is.

### 3.2 Database — `app/services/database.ts` (120 ln)

Schema read directly from `assets/smartswaps.db`:

- `foods` (7,140) — `id` TEXT PK, `name`, `name_de`, `category`, `swiss_category`,
  `health_score` INT, `nutri_grade`, `nova_group` INT, `swap_suggestion_id`, `icon_key`,
  then flat REAL columns `kcal protein_g carbs_g sugars_g fat_g saturated_fat_g fiber_g salt_g`,
  plus `micros` TEXT holding a JSON object.
- `recipes` (955) — `steps` TEXT holding a JSON array.
- `recipe_ingredients` (8,571) — no PK; fetched once with `ORDER BY recipe_id, sort_order`
  and grouped in memory. **Not** converted to a JOIN or to N+1 queries.
- `icon_library` (85) — `icon_key` → `svg_content` (raw OpenMoji SVG) + `source`.

`initDatabase()` **deletes and re-copies the DB out of the bundle on every launch** (the code
says so explicitly: "For simplicity during development, we'll overwrite it"). Reproduced
exactly; recorded in `PORTING_NOTES.md` as intentional-per-source.

**Row order is load-bearing.** `SELECT * FROM foods` has no `ORDER BY`; SQLite returns rowid
order, which fixes the order of `allFoods`, which fixes filter order in `findBestSwaps`,
which fixes tie-break order in the sorts of §5.2 and insertion order of `candidateHits` in
the parser. GRDB over the same file yields the same order. Verified: `foods.json` and the DB
agree on all 7,140 rows **including order** and every field — so `culinary.test.ts`, which
reads `foods.json`, can be ported against the DB with zero behavioural difference.

---

## 4. App state (contexts → observable stores)

| TS | Swift | Notes |
|---|---|---|
| `ProfileContext.tsx` (163) | `ProfileStore` | defaults Female/23/50 kg/170 cm/Lightly Active/stay/`['Balanced']`; Mifflin-St Jeor BMR, activity multipliers, goal offsets, macro split |
| `FavoritesContext.tsx` (78) | `FavoritesStore` | `{foods, swaps, recipes}`, swap id is `"fromId-toId"` |
| `SettingsContext.tsx` (70) | `SettingsStore` | `offLookupEnabled: false`, merged over defaults on load |
| `InventoryContext.tsx` (70) | `InventoryStore` | `ownedFoodIds` = matched foods from **non-list** scans dated ≥ Monday of the current week |

Nesting order in `_layout.tsx` is Profile → Favorites → Settings → Inventory; only Inventory
depends on another (it reads `StorageService`, not a context), so ordering is cosmetic and
preserved anyway.

**⚠ Correction to the brief.** The brief says each context "renders defaults until loaded —
reproduce that, don't block the UI on it." The actual RN code does the opposite: Profile,
Favorites and Settings each `if (!isLoaded) return null;`, so the whole app tree renders
**nothing** until all three AsyncStorage reads resolve. RN code wins — the Swift app shows an
empty root until hydration completes.

Derived (`useMemo` on `profile`): `targetCalories = round(tdee + goalOffset)`;
`targetMacros` = protein/carbs/fat from the split, `sugars = round(kcal*0.1/4)`,
`satFat = round(kcal*0.1/9)`, `fiber = round(kcal/1000*14)`, `salt = 6` (static);
`targetMacroPercentages` with sugars/satFat pinned at 0.1.

Hooks: `useFoods.ts` (95) → `FoodsStore` (module-level session cache of foods + index +
icon library, one load per session); `useRecipes.ts` (295) → `RecipesStore` +
`RecipeMath.swift` (`parseGrams`, `scaleNutrients`, `addNutrients`, `divideNutrients`,
`emptyNutrients`, `estimateTimeDifficulty`); `useDebouncedValue.ts` (25) → `Debounced`;
`useAddedToListAnimation.ts` (32) → `AddedToListAnimation` (spring to 1.06 friction 4, back
to 1, 2 s revert).

---

## 5. Engine — `app/engine/` (Phase 3, ported first, must be proven)

All pure. No UIKit/SwiftUI/Foundation-UI import in `Engine/`.

### 5.1 File map

| TS | ln | Swift | Public surface |
|---|---|---|---|
| `swapAlgorithm.ts` | 484 | `Engine/SwapAlgorithm.swift` | `isLiquid`, `isRawIngredient`, `swapSuppressionReason`, `evaluateSwap`, `findBestSwaps(policy:)`, `findBestSwapsPersonalized`, `SwapPolicy`, `SwapResult` |
| `receiptParser.ts` | 755 | `Engine/ReceiptParser.swift` | `normalize`, `asciiFold`, `matchFoodToOcrText`, `isLikelyProductLine`, `parseReceiptLine`, `parseReceipt`, `MatchDebug` |
| `culinaryFilter.ts` | 381 | `Engine/CulinaryFilter.swift` | `getCulinaryFunction`, `getDishFlavour`, `culinaryVeto`, `pickCulinarySwap` |
| `produceGroups.ts` | 139 | `Engine/ProduceGroups.swift` | `getProduceGroup`, `isProduce` (33 ordered patterns) |
| `resolveProduct.ts` | 230 | `Engine/ResolveProduct.swift` | `resolveProductLine`, `bridgeOffToBls`, `enrichWithOff`, the 4 confidence constants |
| `swapGbm.ts` | 192 | `Engine/SwapGbm.swift` | `FEATURE_NAMES`, `extractGbmFeatures`, `predictSwapQualityGbm` |
| `swapRanker.ts` | 153 | `Engine/SwapRanker.swift` | `predictSwapQuality`, `extractSwapFeatures`, `combineWithExistingScore` — **dead in the app**, kept per its own header note |
| `foodEmbeddings.ts` | 104 | `Engine/FoodEmbeddings.swift` | `embeddingCosine`, `hasEmbedding` |
| `foodAttributes.ts` | 123 | `Engine/FoodAttributes.swift` | `getAttributes`, `hasAttributes`, `ROLE_LABELS`, `PREP_LABELS`, `TIME_LABELS`, `SENSORY_AXES` |
| `foodIndex.ts` | 121 | `Engine/FoodIndex.swift` | `buildFoodIndex` |
| `dietaryFilter.ts` | 148 | `Engine/DietaryFilter.swift` | `isPlantAlternative`, `containsMeatOrFish`, `containsAnimalProduct`, `isAllowedForDiet` |
| `foodVectors.ts` | 82 | `Engine/FoodVectors.swift` | `computeVectorSimilarity` — **dead**, nothing imports it |
| `smartSwaps.ts` | 172 | `Engine/SmartSwaps.swift` | `findSmartSwap` — **dead**, nothing imports it |
| `brandDict.ts` | 91 | `Engine/BrandDict.swift` | `matchBrandDict` |
| `exactLookup.ts` | 12 | `Engine/ExactLookup.swift` | `matchExactLookup` |
| `knownNonMatches.ts` | 14 | `Engine/KnownNonMatches.swift` | `isKnownNonMatch` |
| `germanAbbreviations.ts` | 184 | `Engine/GermanAbbreviations.swift` | `expandGermanAbbreviations` + 4 tables |
| `micronutrients.ts` | 37 | `Engine/Micronutrients.swift` | `getRecommendedMicros(sex:)` — 21 entries with prose |
| `overrideKey.ts` | 33 | `Engine/OverrideKey.swift` | `normalizeOverrideKey` |
| `personalSwapPreferences.ts` | 105 | `Engine/PersonalSwapPreferences.swift` | `recordSwapAccepted/Rejected`, `applyPersonalPreference`, `resetPersonalPreferences` |
| `swapTrainingLog.ts` | 91 | `Engine/SwapTrainingLog.swift` | `logSwapDecision`, `getTrainingLogCount`, `exportTrainingLog`, `clearTrainingLog` |
| — | — | `Engine/JSRegex.swift` | JS-semantics regex shim, see §5.2 |
| — | — | `Engine/JSNumber.swift` | JS `Math.round`, `Number#toString`, `toFixed`, `toLocaleString('de-DE')` |

`recipeSwapAlgorithm.ts` is listed in the brief but is **deleted in the working tree**
(`git status`: `D app/engine/recipeSwapAlgorithm.ts`). Its keyword function model was moved
into `culinaryFilter.ts`, which says so in its own header. Nothing to port. Likewise
`scratch/smokeTestRecipeSwap.ts` is deleted.

### 5.2 JS/Swift semantic traps — all measured, not assumed

**(a) `\b` is not `\b`.** JS `\w` is ASCII-only; ICU/`NSRegularExpression` `\w` is Unicode.
Verified in both runtimes, and it breaks in **both directions**:

| pattern / subject | JS | ICU |
|---|---|---|
| `/\bäpfel\b/` on `"äpfel"` | `false` | `true` |
| `/\bmilch\b/` on `"ämilch"` | `true` | `false` |

This is not academic: `dietaryFilter.hasWord` runs against `name` + `name_de`, and `name_de`
is full of umlauts. `containsKeywords` (swapAlgorithm), `FUNCTION_REGEXES` (culinaryFilter),
`GROUP_PATTERNS` (produceGroups) and `DECLARED_ANIMAL`/`DECLARED_MEAT` are all affected.

Fix, verified working in Swift: `JSRegex` rewrites every pattern before compiling —
`\w`→`[A-Za-z0-9_]`, `\W`→`[^A-Za-z0-9_]`, and `\b` → a lookaround chosen from whether the
adjacent literal is itself an ASCII word char (`(?<![A-Za-z0-9_])` when it is,
`(?<=[A-Za-z0-9_])` when it is not). Confirmed `(?<!…)` lookbehind and `\p{Diacritic}` both
work in `NSRegularExpression`. Every regex in the engine goes through this shim; none is
handed to `NSRegularExpression` raw.

**(b) `Math.round` ≠ `.rounded()`.** Verified: JS `Math.round(-2.5) === -2`, Swift
`(-2.5).rounded() == -3.0`. `JSNumber.round(_:) = (x + 0.5).rounded(.down)`. Reachable —
`evaluateSwap` deltas and `NutrientRow.pct` both take negatives.

**(c) Number → string.** `food/[id].tsx` renders `{value}{unit}` with no formatting, so a
value of `3.4000000000000004` prints in full. `RecipeCard`/`NutrientRow`/`recipe/[id]` use
`val % 1 !== 0 ? val.toFixed(1) : String(Math.round(val))`. Swift's `Double.description`
differs from JS `Number#toString` (`3.0` vs `3`, different exponential thresholds), so
`JSNumber.toString(_:)` implements the ECMA-262 shortest-round-trip algorithm.
`toLocaleString('de-DE')` (used for `targetCalories`, e.g. `2.019 kcal`) is a de_DE
`NumberFormatter`.

**(d) Sort stability + comparators.** JS `Array#sort` is stable and coerces the comparator's
result via `< 0 / > 0`. Swift `sort(by:)` is not guaranteed stable. Every port uses an
explicit stable merge sort (`Array.stableSorted(by:)`) with the comparator translated
literally. Affected sites:
- `findBestSwaps` final sort — primary `b.score - a.score`, secondary `handScore` lookup with
  `?? 0`.
- `matchFoodToOcrText` `allMatches.sort` — the ±0.03 confidence band flips to
  `a.unmatchedCount - b.unmatchedCount`. **This comparator is not a total order** (it is not
  transitive across the band), so the result genuinely depends on the sort algorithm, not
  just on stability. Reproducing it needs V8's TimSort, not just "a stable sort".
  → **Mitigation: `Engine/JSSort.swift` implements V8's TimSort (`ArrayTimSort`) directly.**
  Differential-tested against the TS output over the full corpus in Phase 3.
- `brandDict.sortedBrandKeys` — `b.length - a.length`, ties resolved by **JSON key insertion
  order**. `JSONDecoder` into a `Dictionary` loses that order, so `verifiedBrandMap.json`
  is parsed with an order-preserving reader into `[(String, String)]`.
- `receipts.tsx` week grouping, `recipes.tsx` relevance sort, `RecipeSearchModal` score sort,
  `(tabs)/index.tsx` `worstFirst` — all stable, all ported through the same helper.

**(e) `Map`/`Set` iteration order.** JS is insertion-ordered; Swift `Dictionary`/`Set` are
not. Ordered structures (`OrderedDictionary`/`OrderedSet`, hand-rolled — no swift-collections
dependency) are required at: `candidateHits` and `candidateKeysFor`/`candidateKeysFor4Gram`
in `receiptParser` (their iteration order feeds `candidatesToScore` when
`size <= MAX_CANDIDATES = 120`); `index`/`stemIndex`/`shingleIndex`/`fourGramIndex` in
`foodIndex`; `candidatesMap` and `uniquePurchasedFoods` on the Home screen; `distinct` in
`recipes.tsx` and `ReceiptItemList`; `swapsByFoodId`; `groupedItems` in `ReceiptItemList`
(`Object.entries` order); `ingredientsByRecipe` in `DatabaseService`.

**(f) `Map<FoodItem, number>` keyed by object identity.** `candidateHits` in
`matchFoodToOcrText` keys on the *object*, and `addCand` is called twice for an exact hit to
double-weight it. `FoodItem` as a Swift `struct` has no identity. → foods are loaded once
per session into a `ContiguousArray<FoodItem>` and everything downstream carries a
`FoodRef` (index + `===`-equivalent identity), not a copied struct. This also avoids copying
7,140 structs through every filter chain.

**(g) `null` vs `0`.** `extractGbmFeatures` returns `(number | null)[]`; `predictTree`
branches on `v === null || undefined || NaN` → `defaultLeft`. Modelled as `[Double?]`, never
a sentinel. `embeddingCosine` and `getAttributes` return `nil` for unknown ids and that
`nil` must propagate. `swapRanker.predictSwapQuality` *skips* a null feature's term entirely
rather than standardising a placeholder.

**(h) Int vs Double.** `health_score` is INTEGER in SQLite but every arithmetic use is
floating point in JS. All nutrient and score maths is `Double` in Swift; `Int` appears only
where the value is displayed or indexed.

**(i) `String#split(/\s+/)`** on a leading-whitespace string yields a leading `""`; Swift
`split` drops empties by default. Ported with `omittingEmptySubsequences: false` plus the
explicit `.filter(Boolean)` where the TS has one, and without where it does not.

**(j) `parseFloat` / `Number()`** accept partial prefixes and return `NaN`; `isNaN(Number(w))`
in `foodVectors.tokenize` treats `""` as `0` (not NaN). Ported literally in `JSNumber`.

### 5.3 Data assets — shipped byte-identical, restructured only for load time

| File | Size | Shape | Swift loading |
|---|---|---|---|
| `swapGbm.data.json` | 133 KB | `{featureNames[20], baseScore -0.5259032696775925, learningRate 0.06, trees[200]}`, each tree 6 parallel arrays, ≤31 nodes | decoded once into flat `[Int32]`/`[Double]` |
| `foodEmbeddings.data.json` | 3.8 MB | `{model, dim 384, count 7140, ids[7140], scales[7140], q}` — `q` is 3,655,680 base64 chars, no padding, → 2,741,760 int8 | **converted at build time to a `.bin`** (`Int8` block + ids + scales) and `mmap`ed. Values identical; only the container changes |
| `foodAttributes.data.json` | 215 KB | `{count 7140, bytesPerFood 15, roles[13], prep[4], levels[3], times[5], sensoryAxes[8], ids, q}` | same treatment |
| `data/exactLookup.json` | 18 KB | 332 entries | as-is |
| `data/verifiedBrandMap.json` | 42 KB | 978 entries | as-is, **order-preserving parse** (§5.2d) |
| `data/knownNonMatches.json` | 2.3 KB | as-is |

The hand-rolled base64 decoders in `foodEmbeddings.ts`/`foodAttributes.ts` exist only because
Hermes has no `atob`. They are byte-exact standard base64 for these inputs (verified: both
lengths are exact multiples with no padding), so the build-time conversion is safe — and the
Swift decoder is diffed against the TS one in Phase 3 regardless.

### 5.4 Phase 3 proof plan

The gate before any UI is written:

1. **Ported fixtures** → XCTest. Counts confirmed by running the suites:
   `regression.cases.ts` **55** real OCR lines (currently 55/55 green),
   `off-eval.cases.ts` **105** synthetic branded lines,
   `baseline.cases.ts` **169** cases across 3 buckets,
   `ground_truth.json` **110** hand-verified rows,
   `culinary.test.ts` MUST-VETO / MUST-PASS pairs + function tagging + produce groups +
   fridge pass + policy defaults + dish flavour + 203 end-to-end picks (currently ALL PASS).
2. **`scripts/baseline.snapshot.json`** is the frozen expected output — the Swift engine must
   reproduce its per-case `actual` and per-bucket totals exactly
   (bls-direct 97/121, semantic 2/16, unresolvable 14/32).
3. **Differential fuzz.** `Tools/dump-reference.ts` runs the live TS engine over generated
   inputs and writes JSON; XCTest asserts the Swift port matches within `1e-9` for `Double`
   and exactly for everything else. Coverage per the brief: `evaluateSwap`, `findBestSwaps`,
   `predictSwapQualityGbm`, `embeddingCosine`, `normalize`, `asciiFold`, `parseReceipt` —
   plus, because they carry the traps above, `getEquivalenceGroup`, `isAllowedForDiet`,
   `culinaryVeto`, `getProduceGroup`, `matchBrandDict`, `normalizeOverrideKey`,
   `expandGermanAbbreviations` and `buildFoodIndex` (index keys + per-key member ids in order).
   Sampling: all 7,140 foods for the single-food functions; ~5,000 seeded food pairs for the
   pairwise ones; all fixture lines plus mutations for the parser.
4. `npx tsx` and `node:sqlite` both verified working here (node v26.4.0, tsx 4.23.1), so the
   reference harness runs against the real engine, not a reimplementation.

---

## 6. Networking — `services/offClient.ts` (120 ln)

`OffClient.swift`, `URLSession`. Preserved: `https://search.openfoodfacts.org/search`,
query `?q=<pct-encoded>&page_size=1&fields=product_name,categories_tags,brands`, header
`User-Agent: SmartSwaps/1.0 (Expo receipt scanner; https://github.com/smart-swaps)` and
`Accept: application/json`, `DEFAULT_TIMEOUT_MS = 3000`, `MAX_ATTEMPTS = 2`,
`RETRY_DELAY_MS = 400`, retryable statuses exactly `{429, 502, 503, 504}`, everything else
non-`ok` → immediate `nil`. Any failure resolves `nil`; never throws. Empty query → `nil`.
Off by default (`settings.offLookupEnabled == false`) so the default path makes zero requests.

`encodeURIComponent` and `addingPercentEncoding` differ on `!*'()`; a matching character set
is used so the URL is byte-identical.

---

## 7. Components → SwiftUI (Phase 4)

| Component | ln | Swift | Notes |
|---|---|---|---|
| `SwapComparisonCard.tsx` | 408 | `Components/SwapComparisonCard.swift` | mirrored bar pairs, 8 nutrient rows, expand animation, linked recipes |
| `RecipeCard.tsx` | 364 | `RecipeCard.swift` | `large` + `small` variants, subcategory icon/colour tables, owned-count pill |
| `ReceiptItemList.tsx` | 370 | `ReceiptItemList.swift` | confident >0.72 / potential / notFound <0.45 buckets; haptics §7.4 |
| `NutritionModal.tsx` | 405 | `NutritionModal.swift` | `BlurView intensity 60 tint dark` → `.systemUltraThinMaterialDark`; spring scale 0.8→1 friction 6 tension 60 + 200 ms opacity |
| `RecipeSearchModal.tsx` | 346 | `RecipeSearchModal.swift` | pageSheet, two `LiquidSlider`s |
| `GlassHeader.tsx` | 281 | `GlassHeader.swift` | §7.1 |
| `SelectShoppingListModal.tsx` | 201 | `SelectShoppingListModal.swift` | |
| `SpotlightCard.tsx` | 157 | `SpotlightCard.swift` | |
| `Header.tsx` | 154 | — | **dead code, never imported. Not ported.** (§9) |
| `CoverFlowCarousel.tsx` | 124 | `CoverFlowCarousel.swift` | §7.2 |
| `RecommendedCard.tsx` | 115 | `RecommendedCard.swift` | imported by `(tabs)/index.tsx` but **never rendered** (§9) |
| `HealthPointsCard.tsx` | 94 | `HealthPointsCard.swift` | ring `size 90 strokeWidth 10` |
| `NutrientRow.tsx` | 81 | `NutrientRow.swift` | `pct` clamps to 100; thresholds 40/70 (lower-better), 35/65 (higher-better) |
| `CircularScoreRing.tsx` | 78 | `CircularScoreRing.swift` | `size 40`/`strokeWidth 4` defaults; `r=(size-stroke)/2`; ≥70 green / ≥40 yellow / else red + light bg; label `size*0.35`, weight 700; `-90°` rotation, round cap |
| `LiquidSlider.tsx` | 72 | `LiquidSlider.swift` | step 1, thumb `#FFFFFF`, min track `primaryGreen`, max track `border`, `{max}+ {unit}` at max, labels 0 / max/2 / max+ |
| `SearchModal.tsx` | 24 | `SearchModal.swift` | `presentationStyle="pageSheet"` → `.sheet` |
| `FoodIcon.tsx` | 24 | `FoodIcon.swift` | §7.3 |

### 7.1 `GlassHeader` — progressive blur

`NavBlur` is a `MaskedView` over `BlurView(intensity 12, tint "systemChromeMaterial")` masked
by a vertical `LinearGradient`. Constants: `FADE_EXTENSION = 44`, `FADE_STEPS = 10`,
`alpha = (1-t)²` with `t = (i+1)/10`, formatted `toFixed(3)`, final stop literal
`transparent`. Colours `['#000','#000', ...FADE_COLORS]`, locations
`[0, solidStop, ...fadeLocations]` where `solidStop = headerHeight/(headerHeight+44)` and
`fadeLocations[i] = solidStop + (1-solidStop)*((i+1)/10)`.

Swift: `UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))` in a
`UIViewRepresentable`, masked by a `CAGradientLayer` with **the same 12 stops and the same
locations**, computed from the same formula. Not `.ultraThinMaterial` — the falloff differs
visibly.

Also ported: `HEADER_CONTENT_HEIGHT = 44`; `useCollapseAnim` interpolations
(largeTitle opacity `[0,26]→[1,0]`, translateY `[0,26]→[0,-8]`; blur opacity `[0,38]→[0,1]`;
smallTitle opacity/translateY `[14,34]→[0,1]`/`[6,0]`, all clamped); `LargeTitle`
34/800/tracking 0.37/marginBottom 4; `GlassCircleButton` 44×44 r22, `GlassView` when liquid
glass is available else white 0.9 + shadow (0,2) 0.12 r6; smallTitle 17/600 inset 60/60.

`isLiquidGlassAvailable()` (expo-glass-effect) is true on iOS 26+ → `.glassEffect(.regular,
in: .circle)`; below that, the fallback. Same branch for the tab bar (§8).

### 7.2 `CoverFlowCarousel`

`ITEM_WIDTH = screenWidth * 0.78`, `ITEM_SPACING = (screenWidth - ITEM_WIDTH)/2`, data
tripled, initial offset `(dataLength + initialScrollIndex) * ITEM_WIDTH`, silent
`scrollTo(animated: false)` recentring in `onMomentumScrollEnd`,
`snapToInterval = ITEM_WIDTH`, `decelerationRate = "fast"` (UIKit `.fast` = 0.99), item
`paddingHorizontal 8`, container `marginVertical 4`.

**The brief's description is incomplete** — RN code wins. Per-item interpolation over
`[(i-1)W, iW, (i+1)W]`, all clamped, is **four** transforms, not two:
`scale 0.85→1→0.85`, `opacity 0.5→1→0.5`, **`rotateY '45deg'→'0deg'→'-45deg'`**, and
**`translateX -0.15W→0→+0.15W`**, applied in the order
`perspective(800) → translateX → rotateY → scale`. Swift uses a `UIScrollView`
(`UIViewRepresentable`) with `CATransform3D` (`m34 = -1/800`) applied in that exact order —
SwiftUI's `rotation3DEffect` composes differently and will not match.

### 7.3 `FoodIcon` — SVG

Icons are 85 OpenMoji SVG strings in `icon_library.svg_content`, rendered via `SvgXml`.
Fallback when `icon_key` is null or the SVG fails: the Ionicons glyph from
`getIconForCategory(food.category)`.

**Decision: pre-rasterise at build time into an asset catalog.** 85 icons is a closed set
shipped inside the bundle; a build step renders each at 1x/2x/3x for the largest use (30 pt in
`food/[id]`, 26 pt in Search, 18 pt in `recipe/[id]`). Rationale over the alternatives:
adding an SVG library is a third-party dependency the brief discourages and a runtime parse
cost on every list row; hand-writing a `CAShapeLayer` parser is new untested code in the
visual path for zero benefit at a fixed 85-icon count. Cost: icons stop being resolution
independent — acceptable, since the largest render is 30 pt and 3x covers every device.
Recorded in `PORTING_NOTES.md`. The `icon_library` table is still read (it is the source the
build step consumes, and `icon_key` still selects the asset), so DB behaviour is unchanged.

### 7.4 Haptics

`expo-haptics` → `UIImpactFeedbackGenerator(style: .light)`. Exactly three call sites, all
`ImpactFeedbackStyle.Light`, all wrapped in `try/catch {}`:
`(tabs)/receipts.tsx handleScanPress`, `ReceiptItemList handleEditPress`,
`ReceiptItemList handleDeletePress`. No other haptic anywhere.

### 7.5 Icon mapping

`expo-symbols` (`SymbolView`) maps 1:1 to SF Symbols — `house.fill`, `fork.knife`,
`list.bullet.rectangle`, `magnifyingglass`, `gearshape`, `heart`/`heart.fill`, `xmark`,
`line.3.horizontal.decrease`, `bolt.fill`, `person.fill`, `calendar`, `dumbbell.fill`,
`figure.stand`, `figure.run`, `arrow.down.right.circle.fill`, `cloud.fill`,
`arrow.counterclockwise`, `square.and.arrow.up`, `trash.fill`, `arrow.down.doc`.

Ionicons and Feather need an explicit table. 60+ distinct Ionicons names are used; the
`getIconForCategory` set (`restaurant-outline`, `fish-outline`, `egg-outline`, `leaf-outline`,
`water-outline`, `ice-cream-outline`, `nutrition-outline`, `fast-food-outline`) is the
highest-traffic group — it renders on every list row, every carousel card and every receipt
line. `egg-outline` and `nutrition-outline` have no close SF Symbol; those two are bundled as
the original glyphs. The full table goes in `PORTING_NOTES.md` at Phase 4, with optical size
and weight matched per site.

---

## 8. Navigation & screens (Phases 5–6)

`app/_layout.tsx` → `RootView`: four stores in the environment + a `NavigationStack` with
transparent blurred headers (`headerTransparent`, `headerBlurEffect: 'regular'`,
`headerTitle: ''`, `headerBackButtonDisplayMode: 'minimal'`).

`app/(tabs)/_layout.tsx` branches on `isLiquidGlassAvailable()`. iOS 26+ → native
`TabView` with the liquid-glass bar and SF Symbols. Below → a `UITabBar` with a
`UIBlurEffect(.systemThinMaterialLight)` background (`intensity 90 tint light`), transparent
bar background, `borderTopWidth 0`, tint `primaryGreen` active / `textMuted` inactive,
labels 10 pt, `SymbolView size 22`.

| Route | File | ln | Swift | Presentation |
|---|---|---|---|---|
| Home / Today | `app/(tabs)/index.tsx` | 415 | `Screens/HomeScreen.swift` | tab |
| Recipes | `app/(tabs)/recipes.tsx` | 350 | `RecipesScreen.swift` | tab |
| Receipts | `app/(tabs)/receipts.tsx` | 467 | `ReceiptsScreen.swift` | tab |
| Search | `app/(tabs)/search.tsx` → `SearchScreen.tsx` | 20 + 772 | `SearchScreen.swift` | tab, `mode: .foods` |
| Settings | `app/settings.tsx` | 808 | `SettingsScreen.swift` | pushed |
| Food detail | `app/food/[id].tsx` | 716 | `FoodDetailScreen.swift` | **modal sheet**, swipe-to-dismiss |
| Recipe detail | `app/recipe/[id].tsx` | 907 | `RecipeDetailScreen.swift` | **modal sheet**, swipe-to-dismiss |
| Receipt detail | `app/receipt/[id].tsx` | 500 | `ReceiptDetailScreen.swift` | pushed |
| Scan receipt | `app/scan-receipt.tsx` | 465 | `ScanReceiptScreen.swift` | pushed |

Screen-specific logic worth calling out:

- **Home** — `CAROUSEL_ITEMS = 5`; worst-health-score-first swap expansion with early exit;
  spotlight inserted at `floor(recommended.length/2)`; shopping-list strip masked by a
  horizontal `LinearGradient` at locations `[0, 0.06, 0.94, 1]`; kcal badge opens
  `NutritionModal`; dietary picker is an `ActionSheetIOS` → `.confirmationDialog`.
- **Recipes** — session-scoped `swapIdCache` keyed `"<foodId>|<diet1,diet2>"` (must persist
  across view rebuilds, so it lives on the store, not in the view); relevance sort then
  health score; `limit` 10 → +20.
- **Receipts** — Monday-based week grouping via `getWeekKey`; `LayoutAnimation.easeInEaseOut`
  → `withAnimation(.easeInOut)`; dates via `toLocaleDateString('en-US', …)` → `en_US`
  `DateFormatter`.
- **Search** — dual mode; results are foods + recipes + scans; `useDebouncedValue(query, 250)`
  gates only the swap memo, while the list and the field use the live query.
- **Scan** — OCR → per-line `resolveProductLine` in chunks of 4 with a yield between chunks
  (progress bar) → `enrichWithOff` → `logWeakMatches` → swaps for items with confidence
  > 0.72 → `saveScan`. Thresholds 0.45 (counts toward score) and 0.72 (gets a swap).
- **Recipe detail** — `CULINARY_CANDIDATE_DEPTH = 25`; two-pool produce logic
  (owned-only `{allowWholeFoods: true, minImprovement: 0}` first, then
  `{allowWholeFoods: produce}`); `getDishFlavour` from the recipe's own ingredients;
  swap toggle recomputes totals and a kcal-weighted health score.

`Info.plist`: `NSCameraUsageDescription` + `NSPhotoLibraryUsageDescription` (the RN app calls
`requestCameraPermissionsAsync` for the camera and launches the library with no explicit
request). Orientation portrait. `UIUserInterfaceStyle = Light`.

---

## 9. Dead code found (ported as-is / not ported — no bug fixes)

Per the "no feature changes" rule these are recorded, not corrected:

1. `components/Header.tsx` (154 ln) — never imported anywhere. **Not ported.**
2. `RecommendedCard` — imported by `(tabs)/index.tsx`, never rendered. Ported (the brief
   lists it) but unreferenced, matching the source.
3. `SearchScreen.quickSearches` — declared, never used.
4. **`SearchScreen` CATEGORY filter does nothing.** `category` state is set by the chips in
   the filter panel and listed in the memo's dependency array, but no filter in
   `searchResults` ever reads it. Selecting a category has no effect. Ported as-is.
5. `app/_layout.tsx` registers `<Stack.Screen name="profile" presentation="modal">` — there
   is no `app/profile.tsx`. Route never resolves.
6. `(tabs)/_layout.tsx` registers `<Tabs.Screen name="settings" href={null}>` — settings
   lives at `app/settings.tsx`, i.e. **outside** the tabs group, so this entry refers to a
   route that does not exist. `router.push('/settings')` reaches the root-stack screen.
7. `app/settings.tsx` shadows `expo-clipboard` with a local mock whose
   `setStringAsync` only `console.log`s and whose `getStringAsync` returns `'[]'` — so
   "Export Shopping Lists" reports success having copied nothing, and "Import" always
   imports zero lists. `expo-clipboard` *is* in `package.json`. Ported as the mock.
8. `smartSwaps.ts`, `foodVectors.ts`, `swapRanker.ts` — no app code imports any of them
   (`swapTrainingLog` uses `extractSwapFeatures`, so `swapRanker` is partially live).
   Ported; `swapRanker.ts` says in its own header it is deliberately retained.
9. `tesseract.js` is a dependency but is imported nowhere. Not ported, per the brief.
10. `food/[id].tsx` renders `{value}{unit}` unrounded, so macro rows can show
    `3.4000000000000004g`. Reproduced via `JSNumber.toString`.
11. `(tabs)/index.tsx` and `SearchScreen` both use `.sort(() => 0.5 - Math.random())` to
    shuffle. A comparator returning random values is not a valid sort — the result is
    implementation-defined and not a uniform shuffle. See §10.

All of these go into `PORTING_NOTES.md` under "Bugs faithfully reproduced".

---

## 10. Open items

**⚠ 1 — Fonts.** See §1. Default is SF Pro (what the app actually renders today), *not*
Nunito. Needs a yes/no from you.

**⚠ 2 — `sort(() => 0.5 - Math.random())`.** Two call sites, both purely presentational
(Home carousel filler when fewer than 5 swap candidates exist; SearchScreen's swaps-mode
placeholder list when the query is empty). Because the comparator is inconsistent, the output
distribution is a property of V8's TimSort, not a specification. Byte-identical reproduction
would mean running TimSort with a seeded RNG whose draws match V8's `Math.random()` — which
is unreproducible in principle, since `Math.random()` is unseeded. **Plan: use the
`JSSort.timSort` implementation with a random comparator, giving the same *algorithm* and the
same non-uniform bias, but not the same sequence.** This is the one place where output cannot
be bit-identical, and it is non-deterministic in the source too. Flagging rather than
silently approximating.

**⚠ 3 — `matchFoodToOcrText`'s non-transitive comparator.** Covered in §5.2d. Handled by
porting V8's TimSort rather than assuming stability is enough. Calling it out because it is
the single highest-risk correctness item in the port; if the differential fuzz in Phase 3
shows any mismatch, it will surface here first.

**⚠ 4 — `culinary.test.ts` reads `foods.json`,** which the brief puts out of scope. Verified
`foods.json` and `assets/smartswaps.db` are identical across all 7,140 rows *and* in row
order, so **I will port that suite against the DB.** No decision needed; noting it so the
substitution is on the record.

**⚠ 5 — `recipeSwapAlgorithm.ts` does not exist** (deleted in the working tree). Nothing to
port. Its logic lives in `culinaryFilter.ts`.

**⚠ 6 — Uncommitted work. RESOLVED by verification, no longer blocking.** `git status` shows
10 modified files, 2 deletions and 6 untracked files, three of them load-bearing engine code
(`culinaryFilter.ts`, `produceGroups.ts`, `useDebouncedValue.ts`). Rather than ask, I checked:
`npx tsc --noEmit` is clean, and `npm test` is fully green — db freshness OK, matcher
regression 55/55, culinary suite ALL PASS. The working tree is coherent and self-consistent,
so it is the spec I port. Flag only if you know something the tests do not.

---

## 11. Phase plan and gates

| Phase | Deliverable | Gate |
|---|---|---|
| 0 | this file | **your review** |
| 1 | Xcode project, SPM, bundled assets, `Colors`/`GlobalStyles`, Info.plist | builds, launches to an empty tab bar |
| 2 | models, `DatabaseService`, `StorageService`, stores | 7,140 foods + 955 recipes load; storage round-trips the exact JSON |
| 3 | the whole engine | fixtures green, `baseline.snapshot.json` reproduced exactly, differential fuzz within 1e-9 |
| 4 | 16 components | SwiftUI preview per component |
| 5 | Search → Recipes → Receipts → Home → Settings → detail modals → scan | screenshot diff vs `IMG_2457…2466.PNG` |
| 6 | navigation, modals, haptics, scan→parse→resolve→swap→save | end-to-end |
| 7 | `PORTING_NOTES.md` | side-by-side walkthrough |
