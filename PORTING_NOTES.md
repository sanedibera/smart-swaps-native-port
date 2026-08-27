# PORTING_NOTES.md

Running record of deviations, reproduced bugs and measurements. Started at Phase 3 rather
than Phase 7 so nothing is reconstructed from memory later. **All phases 0-7 complete.**
The engine (phases 0-3) has an automated differential `swift test` gate against the live
TypeScript engine and V8 — the UI (phases 1, 4-7) does not: **no macOS/Xcode/simulator has
ever been available to any container this port has run in**, so the app target has never
been opened in Xcode, built, or run — only validated by manual reading and structural
checks (brace/paren balance, `ruby -rxcodeproj`). Treat every UI file as unverified until
opened on a Mac.

---

## Status

| Phase | State |
|---|---|
| 0 Inventory | done — `PORTING_INVENTORY.md` |
| 1 Skeleton | **partial** — SPM package, resources, compat layer done from before; `SmartSwaps.xcodeproj` generated, app target with `Colors`/`GlobalStyles`/`Typography`, `Info.plist`, and a 4-tab `RootView` added. **"Builds and launches to an empty tab bar" is still unverified** — no macOS/Xcode/simulator is available in this container, see below. |
| 2 Data layer | done, verified row-for-row, **plus** `StorageService`, `FoodsStore`, `RecipeStore`/`RecipeMath`, `ProfileStore`/`ProfileMath`, `FavoritesStore`, `InventoryStore` added in Phase 4 (below) — components needed them to type-check at all. `SettingsStore` is the one piece of PORTING_INVENTORY.md §4 still not ported; nothing in Phase 4 needed it. |
| 3 Engine | **done, gate green** — 18 tests, 0 failures. `Micronutrients.swift` and `RecipeMath.swift` (parseGrams/scaleNutrients/addNutrients/divideNutrients/estimateTimeDifficulty/hydrateRecipes) added in Phase 4 — both were named in PORTING_INVENTORY.md's file map but not yet written; neither has a differential test against the TS original the way the rest of the engine does (see below). |
| 4 Components | **all 15 non-dead components ported** (`Header.tsx` stays unported per §9). SwiftUI `#Preview` on every file, but **none have been opened in Xcode/Previews** — no macOS available, see below. |
| 5 Screens | **done** — all 9 screens ported (4 tabs, Settings, food/recipe/receipt detail, scan flow). No navigation wiring between them yet — that's Phase 6. |
| 6 Integration | **done** — single `NavigationStack` + `Router` wired through `RootView`; all 9 screens navigate for real (no more no-op closures); haptics added at every RN call site; full scan → parse → resolve → swap → save flow reachable end to end. Deep links explicitly out of scope (no `scheme` in `app.json` — see below). |
| 7 Verification | **done** — every screen/component walked RN-vs-Swift for user-action parity (no simulator available, so code-level rather than literal side-by-side); 11 genuine deviations found and fixed, 1 left open (documented); icon-mapping table completed; all 10 reference screenshots reviewed against source. |

Run the suite with `swift test` in `SmartSwapsNative/` (~4 min, no simulator needed).

---

## What the equivalence suite actually proves

Differential against the **live** TypeScript engine and against V8 itself — not against
hand-written expectations. Floats to `1e-9`, everything else exact.

| Test | Volume | Covers |
|---|---|---|
| `JSSortTests` | 2,104 cases | `Array.prototype.sort` vs V8, incl. the non-transitive comparator |
| `DataLayerTests` | 7,140 + 955 + 8,571 + 85 | foods row-for-row **incl. order**, recipes, ingredients, icons |
| `testStringNormalisation` | 14,632 | `normalize`, `asciiFold` |
| `testPerFoodPredicates` | 7,140 × 13 | `isLiquid`, `isRawIngredient`, `swapSuppressionReason`, `isProduce`, `getProduceGroup`, `getCulinaryFunction`, `containsMeatOrFish`, `containsAnimalProduct`, `isPlantAlternative`, `isAllowedForDiet` ×3, raw attributes |
| `testPairwise` | 6,000 pairs | `embeddingCosine`, `evaluateSwap`, all 20 GBM features **including nil-ness**, `predictSwapQualityGbm`, `culinaryVeto` ×2 flavours |
| `testFindBestSwaps` | 2,000 slates | whole pipeline, 4 policies — candidate ids **and** scores |
| `testDishFlavour` | 300 | `getDishFlavour` |
| `testDictionaryTiers` | 168 | `normalizeOverrideKey`, `matchBrandDict`, `matchExactLookup`, `isKnownNonMatch` |
| `testIndexShape` | 4 index sizes | `buildFoodIndex` (5966/2584/13909/6929) |
| `testGermanAbbreviations` | 168 | `expandGermanAbbreviations` |
| `testParseReceiptLine` | 168 | `matchFoodToOcrText` + `parseReceiptLine` |
| `testRegressionSuite` | 55 | `scripts/regression.cases.ts` — **55/55** |
| `testCulinaryGate` | 37 | `scripts/culinary.test.ts` MUST-VETO / MUST-PASS |
| `testMatchesCurrentTypeScriptBaseline` | 169 | per case **and** per bucket |

Baseline buckets, Swift == current TS: bls-direct **96/121** (2 miss, 23 wrong),
semantic **4/16** (6 miss, 6 wrong), unresolvable **13/32** (0 miss, 19 wrong).

---

## Measurements that changed the port

Three things where the obvious implementation was wrong and only measurement caught it.

### 1. V8 does not use TimSort below 8 elements

Found because one differential case (n=7) disagreed. Counting comparator calls on a
descending input separates the algorithms cleanly:

| n | comparator calls | algorithm |
|---|---|---|
| 5 | 8 | binary insertion |
| 6 | 11 | binary insertion |
| 7 | 14 | binary insertion |
| 8 | 7 (= n−1) | TimSort run detection |
| 200 | 199 (= n−1) | TimSort run detection |

**Why it matters.** `matchFoodToOcrText`'s final comparator switches sort key inside a
±0.03 confidence band, so it is not transitive — the winning match is a property of which
comparisons the algorithm performs, not of the comparator alone. My run detector was
swallowing three elements into a "descending" run that V8 never forms, changing the
returned food. `JSSort.swift` now branches to `binaryInsertionSort` for `n < 8`.

### 2. ICU's `\b` disagrees with JS's, in both directions

| pattern / subject | JS | ICU |
|---|---|---|
| `/\bäpfel\b/` on `"äpfel"` | `false` | `true` |
| `/\bmilch\b/` on `"ämilch"` | `true` | `false` |

JS `\w` is ASCII-only; ICU's is Unicode-aware. `dietaryFilter.hasWord` runs against
`name_de`, which is full of umlauts, so this is live, not theoretical — as are
`containsKeywords`, `FUNCTION_REGEXES`, `GROUP_PATTERNS`, `DECLARED_ANIMAL`/`DECLARED_MEAT`.

`JSRegex.swift` rewrites every pattern before compiling: `\w`→`[A-Za-z0-9_]`,
`\d`→`[0-9]`, `\s`→the explicit ECMA whitespace set, and `\b` to a **context-free**
alternation that is true iff exactly one side is an ASCII word char. A naive
`(?<![A-Za-z0-9_])` lookaround is *not* sufficient — it gets `äpfel` wrong. Class-interior
escapes are expanded differently (`\w` contributes members); a comment records that no
pattern in this engine uses `\W`/`\D`/`\S` inside a class, where that expansion would
invert the meaning.

### 3. `scripts/baseline.snapshot.json` is stale

The brief calls it "the frozen expected output" that the Swift engine must reproduce
exactly. It cannot be, because **the TypeScript engine no longer reproduces it either**.
The snapshot is dated `2026-07-19T21:22:59.133Z`; the working tree's engine changes
(`swapAlgorithm.ts`, `dietaryFilter.ts`, the new `culinaryFilter.ts`/`produceGroups.ts`)
moved **30 of its 169 cases**. Running `npx tsx scripts/baseline-eval.ts` today produces
96/2/23, 4/6/6, 13/0/19 — the numbers the Swift port produces.

Resolution: gate on a snapshot regenerated from the current tree
(`Fixtures/baseline-current.json`), and pin the drift in `testCommittedSnapshotDrift` so
it stays visible rather than being quietly absorbed. Examples of the 30:
`Pringles Original 165g` null→`bls0327`, `Landliebe Schlagsahne 30% 200ml`
`bls0699`→`bls0344`, `KIDNEY BOHNEN` `bls0658`→`bls1741`.

**This needs your call**: either regenerate and commit `baseline.snapshot.json` from the
current tree, or treat the 30 moves as regressions to investigate. I have not touched the
committed file.

---

## Deviations from the brief

| Deviation | Why |
|---|---|
| **System `SQLite3`, not GRDB/SQLite.swift** | Four read-only queries, no JOIN, no writes. An ORM adds a network-fetched dependency and a layer between the port and SQLite's row order, which §3.2 established is load-bearing. |
| **`foodEmbeddings`/`foodAttributes` `.data.json` → `.bin` + meta at build time** | Explicitly allowed by the brief. 3.8 MB JSON with a 3.6 M-char base64 payload became a 2.74 MB mmap-able blob. Numbers untouched — the 6,000-pair cosine diff at 1e-9 is the proof, so the hand-rolled Hermes base64 decoder has no Swift counterpart. |
| **SF Pro, not Nunito** | Your decision, and it matches the running app: the tab bar names `Nunito_500Medium` but no font file is bundled, nothing calls `useFonts()`, and no other `fontFamily` appears anywhere. |
| **`SmartSwapsKit` as an SPM package** | Lets the Phase 3 gate run as `swift test` in ~4 min with no simulator. The app target will depend on it. |
| **App target has no separate `Resources/` data bundle** | `smartswaps.db` and the `.data.json`→`.bin` assets already ship as `SmartSwapsKit`'s package resources (Phase 2/3). The app target consumes them through the package's `Bundle.module` rather than duplicating a second copy, per PORTING_INVENTORY.md §0's own target layout listing `Resources/` once. Not a behavioral change, just avoids two copies of a 7.6 MB DB. |

---

## Phase 4 — shared components

All 15 non-dead `components/*.tsx` ported to `SmartSwapsNative/SmartSwaps/Components/*.swift`,
one file each, same names. `Header.tsx` stays unported (§9 — never imported anywhere).

**What this needed that didn't exist yet.** Several components reach into RN contexts/hooks
(`useFavorites`, `useProfile`, `useInventory`, `useRecipes`, `useFoods`) that PORTING_INVENTORY.md
§4 scoped to Phase 2 but were never written — Phase 2's "done" status only covered
`DatabaseService`/`KeyValueStore`. Rather than stub these out, they were built for real now,
since a component that can't reach its data isn't a faithful port of one that can:

- `Models/Recipe.swift`, `Models/Profile.swift`, `Models/Inventory.swift` (new `SmartSwapsKit`
  types: `Recipe`, `RecipeIngredient`, `Profile` + its enums, `ScanRecord`, `FavoritesState`).
- `Engine/Micronutrients.swift`, `Engine/RecipeMath.swift` (new `SmartSwapsKit` pure functions —
  named in PORTING_INVENTORY.md's file map, not yet written).
- `Data/StorageService.swift` (new — port of `services/storage.ts`, the scan/interaction log).
- `State/{Foods,Profile,Favorites,Inventory,Recipe}Store.swift` (new, app-target
  `ObservableObject`s — `SettingsStore` is the one PORTING_INVENTORY.md §4 store nothing here
  needed, so it's still unwritten). Components take these via `@EnvironmentObject`, matching
  the RN pattern of reaching into context internally rather than through props — `RootView`
  now instantiates and injects all five, nested Profile → Favorites → Inventory (Settings
  omitted) per §4, and reproduces its "renders nothing until Profile+Favorites finish loading"
  correction to the brief.

**Not differentially tested.** Unlike the Phase 3 engine, `RecipeMath`/`Micronutrients`/
`ProfileMath` have no `swift test` gate diffing them against the live TS originals — Phase 3's
proof method (dump-then-diff via `npx tsx`) wasn't run for them here. `ProfileMath`'s BMR/macro
arithmetic and `RecipeMath.parseGrams`'s regex were checked by hand against
`ProfileContext.tsx`/`useRecipes.ts`, which is weaker than the rest of this port's standard.
Recommend a proper differential fixture before Phase 3's gate is considered to cover them.

**Not verified in Xcode at all.** No macOS/Xcode is available in any container this port has
run in, so none of these 15 `#Preview`s have actually been rendered, and the code has only been
checked by reading it and a brace/paren balance script — not compiled. Treat every file here as
unverified until opened on a Mac.

**Deviations and approximations, each disclosed in the file's own header comment:**

| File | Deviation |
|---|---|
| `FoodIcon.swift` | Always takes the SF Symbol fallback path — the OpenMoji SVG rendering pipeline (pre-rasterise at build time, per PORTING_INVENTORY.md §7.3) needs a build step this container can't run. `iconLibrary` is threaded through so wiring the real path later doesn't change the call signature. |
| `FoodsStore.swift` (`getIconForCategory`) | Ionicons → SF Symbol map is a best-effort guess (`fork.knife`, `fish`, `carton`, `leaf`, `drop`, `birthday.cake`, `basket`, `takeoutbag.and.cup.and.straw`), **not checked against a live SF Symbols catalog**. `egg-outline` (→ `carton`) and `nutrition-outline` (→ `basket`) have no close SF equivalent at all, exactly the two PORTING_INVENTORY.md §7.3 already flagged as needing bundled originals instead — this port approximates rather than bundling. Verify every name in Xcode's SF Symbols app before shipping. |
| `CoverFlowCarousel.swift` | Reimplemented on `DragGesture` over a fixed `HStack` rather than a real `ScrollView`, because view-aligned scroll-snap is iOS 17+ and the deployment target is 16.4. Geometry (scale/opacity/±45° Y-rotation/inward translateX) and the tripled-data loop-jump are faithful; the momentum/deceleration feel of `decelerationRate="fast"` is a SwiftUI spring, not UIScrollView physics — different curve, same idea. |
| `GlassHeader.swift` | `.bar` material stands in for `tint="systemChromeMaterial"` (closest SwiftUI equivalent — same material UIKit's own nav/tab bars use). `scrollY` is a plain `CGFloat` a hosting screen must feed in (no `Animated.Value` equivalent exists); Phase 5 screens need to track their own scroll offset via a `PreferenceKey` and pass it through. The `isLiquidGlassAvailable()`/`NativeTabs`-style liquid-glass button branch is still not implemented — `GlassCircleButton` always renders the white-circle fallback, same open item as `RootView`'s tab bar. |
| `ReceiptItemList.swift` | The shopping-list `recipeName` grouping (`(item as any).recipeName` in the source) has no home on `ParsedReceiptItem`/`ScanRecord` — that's an ad-hoc field the RN scan object carries, not part of either type's real shape. Renders one ungrouped "Other Items"-style section for now; revisit when Phase 6 wires up real scan data and it's clear where that field should live. `router.push` calls become an `onSelectFood: (String) -> Void` closure, same style already used by `RecipeCard`/`SwapComparisonCard`. |
| `Models/Inventory.swift` (`PersistedReceiptItem`) | `ParsedReceiptItem` (Phase 3) holds a live `FoodItem` **class** reference, which is correct for in-memory matching but can't round-trip through `Codable` the way JS serializes the matched food's plain object into `@smart_swaps_scans`. Added a separate `Codable` shape (`matchedFoodId: String?`) with a `resolved(in:)` bridge back to `ParsedReceiptItem`, rather than making the engine's own matched-object identity semantics (§5.2c) `Codable`. |
| `SearchModal.swift` | RN's `SearchModal` self-presents a `<Modal>`; this port renders bare content and expects the caller to present it via SwiftUI's `.sheet(...)` modifier instead (see `ReceiptItemList.swift`'s usage) — modifier-driven presentation is the SwiftUI idiom, RN's self-presenting component isn't. `SearchScreen()` itself is still the Phase 1 placeholder. |
| `Data/DatabaseService.swift` / `RecipeMath.hydrateRecipes` | `recipe_ingredients` has `grams`/`kcal` DB columns that `RecipeIngredientRaw` already reads (Phase 2), but `RecipeMath.hydrateRecipes` ignores both and recomputes them from `raw_text` via `parseGrams`/`scaleNutrients`, because that's what the TS source actually does (`useRecipes.ts` never reads those DB columns either). Whatever those columns hold is unused by the real app — flagging so a future reader doesn't assume it's a bug that they're dead. |

---

## Phase 5 — screens (in progress)

All 4 tab screens ported to `SmartSwapsNative/SmartSwaps/Screens/*.swift`, replacing the
Phase 1 placeholders: `SearchScreen.swift` (from `SearchScreen.tsx`, 772 ln),
`RecipesScreen.swift` (`(tabs)/recipes.tsx`, 350 ln), `ReceiptsScreen.swift`
(`(tabs)/receipts.tsx`, 467 ln), `HomeScreen.swift` (`(tabs)/index.tsx`, 415 ln, titled
"Groceries"). Settings, the 3 detail/modal screens (food, recipe, receipt), and the scan flow
are still outstanding.

**New shared infrastructure this needed:**

- `DesignSystem/ScrollOffset.swift` - `TrackableScrollView`/`ScrollOffsetReporter`, a
  `PreferenceKey`-based scroll offset tracker every `GlassHeader`-hosting screen uses to feed
  `scrollY` (SwiftUI has no `Animated.ScrollView` equivalent - see `GlassHeader.swift`'s own
  header comment from Phase 4). Compatible back to iOS 14, unlike the iOS 17+
  `onScrollGeometryChange` alternative.
- Every screen's (and several Phase 4 components') optional closure/string properties needed
  an explicit `= nil` default that Phase 4 had omitted - Swift's synthesized memberwise init
  does NOT default an `Optional`-typed property just because its type can hold `nil`; without
  the explicit default, `RootView`'s zero-argument `HomeScreen()` etc. would not compile. Fixed
  across `Components/` and `Screens/` in this pass; flagging since it's an easy mistake to
  reintroduce when adding new closures later.

**`RootView.swift`** now instantiates all 4 tab screens for real (previously empty placeholder
`Color` views).

**`useFocusEffect` -> `.onAppear`.** `SearchScreen`/`ReceiptsScreen` re-fetch scans every time
their RN screen regains focus (tab reselect, back-navigation); `.onAppear` fires on first
appearance and on navigating back to the view, but not on every tab reselect within a
`TabView` the way `useFocusEffect` does. Not fixable cleanly without the real `NavigationStack`
Phase 6 will introduce - flagged rather than silently treated as equivalent.

**Deviations and simplifications, each disclosed in the file's own header comment:**

| File | Deviation |
|---|---|
| `HomeScreen.swift` | The `ActionSheetIOS`/`Alert.alert` dietary-preference picker becomes a `.confirmationDialog` - the RN Android branch (one `Alert.alert` row per option) has no separate Swift path since this port is iOS-only. |
| All 4 screens | `router.push` calls become `onNavigateTo*` closures, all defaulting to `nil` (no-op) until Phase 6 wires a real `NavigationStack`. `useMemo`'s explicit dependency arrays have no SwiftUI equivalent - filtering/sorting logic is plain computed properties that SwiftUI recomputes on every body evaluation rather than only when RN's listed dependencies change. Functionally equivalent, not performance-equivalent; worth profiling once real data volumes (7,140 foods) are wired through in Phase 6. |
| `SearchScreen.swift` swap mode | Same `sort(() => 0.5 - Math.random())` non-determinism as the Home carousel filler (Phase 3/4's flagged open item) - `JSSort.sorted` with a random comparator, same algorithm and bias, not the same sequence. |

**A real bug caught and fixed in this pass:** `Sex`, `ActivityLevel`, `WeightGoal`,
`DietaryPreference` (`Models/Profile.swift`, added in Phase 4) were declared
`String, Codable, CaseIterable` only - no `Equatable`/`Hashable`. Swift does not synthesize
either for a raw-value enum unless the type explicitly declares conformance; every `==`,
`.contains(_:)`, and `ForEach(id: \.self)` against these types across Phase 4/5 (dietary
preference filters in `FoodsStore`/`RecipesScreen`/`RecipeSearchModal`, the Home carousel's
`.confirmationDialog`, Settings' diet toggles) would not have compiled. Fixed by adding
`Hashable` (which implies `Equatable`) to all four enums in `Models/Profile.swift` - a single,
central fix rather than one per call site. Flagging because nothing caught this except reading
the code line by line; there is still no `swift test`/Xcode compile gate on any app-target file.

### Settings screen

Ports `app/settings.tsx` (808 ln) to `Screens/SettingsScreen.swift`. Needed three more
`SmartSwapsKit` pieces PORTING_INVENTORY.md's file map named but nothing had built yet:
`Engine/SwapRanker.swift` (153 ln - dead in the app itself, but `SwapTrainingLog` calls its
`extractSwapFeatures`), `Engine/SwapTrainingLog.swift`, `Data/MatchLog.swift`. Plus
`State/SettingsStore.swift` (the last of PORTING_INVENTORY.md §4's four context stores -
`ProfileStore`/`FavoritesStore`/`InventoryStore` landed in Phase 4) and
`DesignSystem/ActivityView.swift` (a `UIActivityViewController` wrapper standing in for RN's
`Share.share`, since the export buttons' content is only known after an async, possibly-
throwing load - not a good fit for SwiftUI's declarative `ShareLink`). `RootView` now injects
`SettingsStore` too, nested Profile → Favorites → **Settings** → Inventory per §4, gating the
"renders nothing until loaded" behavior on all three providers that have it (Inventory doesn't,
matching the source).

**Reproduced deliberately, not a new bug:** `settings.tsx` shadows `expo-clipboard` with an
inline no-op mock (`PORTING_NOTES.md`'s existing "Bugs faithfully reproduced" #7) - `getStringAsync`
always returns `"[]"`. `SettingsScreen.swift`'s private `MockClipboard` enum reproduces the
exact same behavior, so Export/Import Shopping Lists remain silently non-functional here too,
matching the running RN app rather than "fixing" it.

**Deviations:** `ActionSheetIOS`/bottom-sheet `<Picker>` → SwiftUI `.wheel`-style `Picker` in a
`.sheet` with `.presentationDetents` (a native bottom sheet, matching the RN "iOS style bottom
sheet" comment); the numeric input modal uses the same centered-transparent-overlay pattern
`NutritionModal.swift` (Phase 4) established, not a system `.sheet` (which anchors to the
bottom, not centered, and would look wrong for this one). `.presentationDetents`/`.wheel`
picker styling has not been checked in an actual iOS Settings-style bottom sheet since no
Xcode/simulator is available - visually unverified like everything else in Phases 4-5.

---

## Phase 5 continued — detail screens and the scan flow (Phase 5 now done)

Ports the remaining 4 screens: `FoodDetailScreen.swift` (`app/food/[id].tsx`, 716 ln),
`RecipeDetailScreen.swift` (`app/recipe/[id].tsx`, 851 ln), `ReceiptDetailScreen.swift`
(`app/receipt/[id].tsx`, 500 ln), `ScanReceiptScreen.swift` (`app/scan-receipt.tsx`, 465 ln).
All 9 screens from PORTING_INVENTORY.md §8 now exist.

**A significant correction to PORTING_INVENTORY.md, found by reading the actual source
(brief rule 1: "the RN code wins") rather than trusting the earlier summary:**
`app/engine/recipeSwapAlgorithm.ts` and `app/engine/foodVectors.ts` are both listed in
PORTING_INVENTORY.md §5.1 as **deleted from the working tree / dead code**. Neither is true
in the tree this phase actually read — `recipe/[id].tsx` imports and calls
`findBestRecipeSwap` directly, which itself imports `computeVectorSimilarity` from
`foodVectors.ts`. Both are real, live, and required for the recipe detail screen's ingredient
swap suggestions. Ported as `Engine/RecipeSwapAlgorithm.swift` and `Engine/FoodVectors.swift`
— the inventory was evidently written against a different tree state than what's in this repo
now; treat its "dead code" claims for these two files as stale, not authoritative. Also added
`Services/NativeOcr.swift` — `modules/native-ocr/ios/NativeOcrModule.swift` lifted near-
verbatim per the brief's own instruction, with only the `ExpoModulesCore` wrapper replaced by
`async throws`. Kept in the app target (not `SmartSwapsKit`, which also targets macOS for
`swift test` and has no `UIKit`).

**Two real, would-not-compile bugs caught and fixed in this pass, both worth flagging because
nothing but reading the code line-by-line caught them — there is still no build gate on any of
this:**

1. **`FoodItem.health_score` is `Double`** (matches the JS `number` type and the differential-
   tested Phase 3 data layer exactly), but numerous Phase 4/5 view-layer types
   (`SpotlightCard.score`, `SearchScreen.Row.score`, `SwapComparisonCard`/`SearchScreen`'s
   `improvement`) declared themselves `Int` and were fed `food.health_score` or a difference
   of two `health_score`s directly - a type mismatch that would not compile. Fixed by wrapping
   every such site in `JSNumber.roundToInt(...)`, which is also the behaviorally-correct
   choice (matches `Math.round`/JS `Number#toString` truncation semantics the rest of the port
   already standardizes on), not just a type-checker workaround. `Recipe.health_score` is
   correctly `Int` (computed via `JSNumber.roundToInt` in `RecipeMath.hydrateRecipes`) and was
   never affected.
2. **Two `.onChange(of:)` call sites used the iOS 17+ two-parameter closure form**
   (`RecipeSearchModal.swift`, `ScanReceiptScreen.swift`) on a project whose deployment target
   is 16.4. Fixed to the iOS 14+ single-parameter form.

**Deviations, each disclosed in the file's own header comment:**

| File | Deviation |
|---|---|
| `FoodDetailScreen.swift` / `RecipeDetailScreen.swift` | Both presented as sheets (matches PORTING_INVENTORY.md §8's `presentation: 'modal'`), so the native-stack back chevron + `headerRight` favorite button become a small custom floating header (close + heart, `GlassCircleButton` styling) with `NavBlur` behind it, rather than `Stack.Screen`'s `headerRight`. `RecipeDetailScreen`'s active-totals/ingredient-swap computation re-runs on every body evaluation (no `useMemo` equivalent), same tradeoff already flagged for the tab screens. |
| `ReceiptDetailScreen.swift` | Title-edit-on-blur has no clean SwiftUI equivalent without `@FocusState` plumbing not yet wired here - only edit-and-submit (return key) saves, not tap-away. |
| `ScanReceiptScreen.swift` | Camera capture is a `UIImagePickerController` wrapper (SwiftUI has no built-in camera view); library selection uses `PhotosPicker` (`PhotosUI`) instead of `expo-image-picker`'s library mode - a modern SwiftUI-native equivalent, not a behavior change. The picked image round-trips through a temp JPEG file so `NativeOcr.recognize(uri:)` keeps the same file-URI contract the original module had. |
| `ReceiptDetailScreen.swift` / `ScanReceiptScreen.swift` "Add Item via Search" | RN's `handleAddItem` accepts either a `FoodItem` or a whole `Recipe` (adding all its ingredients, tagged with `recipeName`). `SearchModal.swift`'s `onSelect` only carries a `FoodItem` (a Phase 4 simplification, see that phase's notes) - selecting a recipe from this flow isn't wired yet. Revisit alongside the still-open `ParsedReceiptItem`/`ScanRecord` `recipeName` gap already noted in Phase 5's tab-screen section. |

None of these 4 files have been opened in Xcode either - same standing caveat as every other
UI file in this port. Phase 5 is now complete; Phase 6 (navigation, modal presentation, deep
links, haptics, the scan → parse → resolve → swap → save flow end to end) is next. Every
`onNavigateTo*`/`onSelect*` closure across all 9 screens currently defaults to a no-op `nil` -
`RootView` wires the 4 tab screens but nothing navigates to Settings or any detail screen yet.

---

## Phase 6 — Integration (navigation, modals, haptics, the full scan flow)

Replaces every `onNavigateTo*`/`onSelect*` closure-passing scheme from Phases 4-5 with a
single shared `Router` (`App/Router.swift`, `@MainActor final class Router: ObservableObject`),
mirroring `app/_layout.tsx`'s expo-router tree: one root `Stack` wrapping `(tabs)`, with
`food/[id]` and `recipe/[id]` declared `presentation: 'modal'` and everything else (Settings,
`receipt/[id]`, `scan-receipt`) an implicit plain push.

**Architecture.** `RootView` now owns one `NavigationStack(path: $router.path)` wrapping the
`TabView`, with a single `.navigationDestination(for: Router.PushRoute.self)` switching on
`.settings` / `.receipt(id)` / `.scan`. The two modal routes are separate `.sheet(item:)`
modifiers driven by `router.presentedFoodId`/`presentedRecipeId` (`@Published var: String?`),
converted to `Identifiable` via a small `IdentifiableID` wrapper struct since a bare `String`
can't drive `.sheet(item:)` directly. `router.selectedTab` backs the `TabView`'s own
`selection:` binding. Every screen that needs to navigate now takes `@EnvironmentObject private
var router: Router` instead of a bag of closures - this collapses e.g. `HomeScreen`'s four
`onNavigateTo*` params, `RecipesScreen`/`ReceiptsScreen`/`SearchScreen`/`RecipeDetailScreen`'s
one each, and `ReceiptItemList`'s `onSelectFood`, down to zero navigation params on all of them.

**`FoodDetailScreen`'s in-place replace vs. `RecipeDetailScreen`'s external navigate.** RN's
`food/[id].tsx` `handleAcceptSwap` calls `router.replace(...)` to swap the *currently open*
modal's content for the accepted-swap food, without closing and reopening it. There's no
direct SwiftUI equivalent to "replace the item driving an already-presented `.sheet(item:)`
that also survives without re-triggering the sheet's appear/dismiss transition, so
`FoodDetailScreen` was changed to own its displayed food as internal `@State private var
currentFoodId: String` (seeded from an `init(foodId:onClose:)`) rather than reacting to
`router.presentedFoodId` changing underneath it; `acceptSwap` now just reassigns
`currentFoodId` in place. `RecipeDetailScreen`, by contrast, genuinely needs to open a *new*
food sheet on top when an ingredient or swap suggestion is tapped (RN's equivalent there is a
real `router.push`, not a `replace`), so it correctly goes through `router.openFood(id)`.

**`ReceiptDetailScreen` push-vs-modal header correction.** Built in Phase 5 with the same
`GlassCircleButton` "X" close-button chrome as the genuinely-modal `FoodDetailScreen`/
`RecipeDetailScreen`, but per `app/_layout.tsx` only `food/[id]` and `recipe/[id]` are declared
`presentation: 'modal'` — `receipt/[id]` is a plain push, so RN shows the root `Stack`'s native
back chevron (`headerBackButtonDisplayMode: 'minimal'`), not a custom X. Corrected in this
phase: removed the custom floating header entirely, replaced the `onBack: () -> Void` param
with `@Environment(\.dismiss)`, moved the (still-editable, still-tappable) title into a
`.toolbar { ToolbarItem(placement: .principal) { ... } }`, and set
`.toolbarBackground(.hidden, for: .navigationBar)` + `.navigationBarTitleDisplayMode(.inline)`
so the source's `headerBlurEffect: 'none'` + separately-rendered `<NavBlur>` still reads as one
feathered fade layered *behind* the content rather than fighting an opaque system material.

**`SearchModal` bug fix.** Found while wiring `ReceiptItemList`'s correction-picker sheet:
`SearchModal.body` called bare `SearchScreen()`, silently dropping its own `mode`/`onSelect`/
`rawText` properties entirely — a Phase 4 leftover written before `SearchScreen` existed for
real (Phase 5). Now forwards all three; `onSelect` narrows `SearchSelection` down to the
`.food` case only, matching this modal's `FoodItem`-only contract (same "recipe selection not
wired here" simplification already flagged for `ReceiptDetailScreen`/`ScanReceiptScreen`'s
"Add Item via Search" in Phase 5's notes).

**Haptics.** `Services/Haptics.swift` wraps `UIImpactFeedbackGenerator(.light)` behind a single
`Haptics.light()` call, matching every `expo-haptics` `impactAsync(ImpactFeedbackStyle.Light)`
call site found by grep: `ReceiptsScreen`'s "navigate to receipt" rows (RN's
`handleScanPress`), `ReceiptItemList`'s edit/delete buttons. Deliberately *not* added to
`ReceiptsScreen`'s scan button or `HealthPointsCard`'s scan button — RN doesn't haptic those
either, confirmed by reading the source rather than adding it everywhere for consistency.

**`RecipesScreen`'s dead search-sheet state, confirmed not a bug.** `RecipesScreen` renders a
`RecipeSearchModal` gated on `searchVisible`, but grepping `app/(tabs)/recipes.tsx` shows
`setSearchVisible(true)` is never called anywhere in the source — the sheet is genuinely
unreachable in the original RN app too. Left as-is (unreachable `@State`, no trigger wired),
per rule 3 (reproduce bugs/dead paths faithfully, don't silently "fix" them).

**Explicit non-goal: deep linking.** The brief's Phase 6 description mentions deep links, but
`app.json` has no `"scheme"` key (confirmed by grep) - there is nothing for `expo-router` to
register as a URL scheme in the first place, so there's no native `Info.plist` `CFBundleURLTypes`
entry to port either. Recording this explicitly rather than leaving it silently undone.

**Standing performance tradeoff, not new to this phase but only now exercised end-to-end:**
`FoodsStore.load()` is synchronous and blocks the main actor during `RootView.onAppear`. This
was a deliberate risk-averse choice in Phase 4 (no compiler/simulator available to verify a
background-dispatch refactor against a non-`Sendable` `DatabaseService`), and now that the full
tab bar actually mounts and calls it for real, it causes a one-time hitch on cold launch before
the first tab's content appears. Flagging as an open item for whenever real device/simulator
profiling becomes possible.

No changes needed to `HomeScreen`/`RecipesScreen`/`ReceiptsScreen`/`SearchScreen` beyond
swapping their closure params for `@EnvironmentObject private var router: Router` and updating
each call site 1:1 — no new behavioral decisions there. `xcodeproj` regenerated to pick up
`App/Router.swift` and `Services/Haptics.swift`; both confirmed present in the app target's
source list via `ruby -rxcodeproj`. As with every other phase, none of this has been opened in
Xcode/Simulator - unverified beyond manual reading, brace/paren balance checks (no new
mismatches beyond the two pre-existing false positives in `JSSort.swift`/`ReceiptParser.swift`,
both from string/comment content, already documented), and `ruby -rxcodeproj` structural checks.

---

## Bugs faithfully reproduced

Per rule 3 — ported as-is, recorded here.

1. **DB delete-and-recopy on every launch.** `initDatabase()` deletes the working copy and
   re-copies from the bundle each time ("For simplicity during development..."). A user's
   database never survives a restart. Preserved.
2. **`nova_group` is NULL for all 7,140 rows**, so every NOVA branch in
   `smartSwaps.findSmartSwap` is dead. (That module is itself unreferenced.)
3. **83 NULL macro cells** (protein 23, satfat 23, fibre 27, fat 10). TS carries `null`
   into arithmetic. Verified 0.0 is behaviourally identical here: JS coerces `null`→0 in
   arithmetic *and* relational comparison, `||` treats them alike, and nothing compares a
   nutrient with `==`/`===` — checked by grep across `app/`, `components/`, `SearchScreen.tsx`.
4. **`OverrideStore.get()` returns null until `load()` completes.** The offline eval never
   calls `load()`, so tier 1 is inert there — and reproducing the baseline depends on it.
5. **`brandDict` keys with dots** (`sort.`, `clas.`, `m.i.`) can never match, because dots
   are stripped before the lookup. Preserved.
6. **Unrounded nutrient rendering.** `food/[id].tsx` renders `{value}{unit}`, so a macro can
   display as `3.4000000000000004g`. `JSNumber.toString` implements ECMA-262
   `Number::toString` for this. *(UI phase — not yet exercised.)*
7. **Dead code** — ported or skipped as noted in `PORTING_INVENTORY.md` §9:
   `components/Header.tsx` never imported (not ported); `RecommendedCard` imported but
   never rendered; `SearchScreen.quickSearches` unused; **`SearchScreen`'s CATEGORY filter
   is wired to state that no filter ever reads**, so selecting a category does nothing;
   `app/_layout.tsx` registers a `profile` modal route with no file; `(tabs)/_layout.tsx`
   registers a `settings` tab route that lives outside the tabs group; `settings.tsx`
   shadows `expo-clipboard` with a mock that only `console.log`s, so Export/Import Shopping
   Lists silently do nothing.
8. **`SearchScreen`'s favorite heart uses the wrong type key for every non-food row.**
   `SearchScreen.tsx:474-478`'s result-row renderer hardcodes `'food'` as the favorite-type
   argument to both `toggleFavorite` and the live `isFavorite` read, regardless of whether the
   row is actually a food, recipe, shopping list, or receipt (all four share this render path).
   Self-consistent (both read and write use the same wrong key, so the heart still visibly
   toggles), but a recipe/list/receipt "favorite" from this screen is actually stored under the
   food-favorites key. Found in Phase 7; Swift previously diverged by hardcoding the heart to
   `false` for non-food rows instead, which was *more correct* than RN — fixed to match RN's
   bug exactly (see Phase 7 notes below).

---

## Still uncertain / open

- **`sort(() => 0.5 - Math.random())`** (Home carousel filler, SearchScreen placeholder).
  An inconsistent comparator is not a specification and `Math.random()` is unseeded, so
  byte-identical output is impossible in principle. Plan: same algorithm via `JSSort`, same
  non-uniform bias, different sequence. Both sites are purely decorative. **Not yet reached.**
- **Case-insensitive matching (`i` flag).** ICU does full Unicode case folding, JS's
  non-unicode mode does simple folding; `ß`/`ss` could in principle differ. No divergence
  appeared across 14,632 strings and 168 parse lines, but it is unproven in general.
- **Xcode app target exists but is unbuilt-and-unverified.** `SmartSwaps.xcodeproj` is now
  generated (`Tools/generate-xcodeproj.rb`, via the `xcodeproj` Ruby gem — no `xcodegen`
  available, same as before) and references the app-target sources, `Info.plist`, and a
  local package dependency on `SmartSwapsKit`. It round-trips through `xcodeproj` cleanly,
  but **no `xcodebuild`/simulator is available in any container this port has run in**, so
  "builds and launches to an empty tab bar" has never actually been demonstrated. Needs a
  real Mac to confirm; flagging rather than claiming a gate that isn't proven.
- **`(tabs)/_layout.tsx`'s `NativeTabs` (Liquid Glass, iOS 26+) branch not ported.**
  `RootView.swift` only implements the `ClassicTabLayout` fallback (blurred/transparent
  `UITabBar`, tinted `primaryGreen`/`textMuted`, SF Symbols, 10pt labels). The
  `isLiquidGlassAvailable()` branch is deferred rather than guessed at with no real tab
  content yet to verify it against — revisit alongside Phase 5/6.

---

## Phase 7 — Verification pass

No simulator/Xcode has been available at any point in this port (flagged since Phase 1), so a
literal "run both apps side by side" was never possible. What this phase actually did instead:
read all 10 reference screenshots (`IMG_2457.PNG`-`IMG_2466.PNG`) against the corresponding
Swift source for copy/color/layout fidelity, then did an exhaustive line-by-line RN-vs-Swift
comparison of every screen and shared component's user-triggered actions (three parallel
passes: tab screens, detail/settings screens, scan flow + remaining components), verifying
each `onPress`/`onChangeText`/toggle/gesture has a faithful Swift equivalent — same trigger,
same resulting state change, same copy text, same alert titles/messages/buttons. Eleven
genuine deviations surfaced (all introduced during this port, not RN bugs — so fixed to match
RN exactly, not reproduced):

1. **`SearchScreen`'s favorite heart was dead for non-food rows.** RN's `SearchScreen.tsx:474-478`
   hardcodes `'food'` as the favorite-type key for *every* result row regardless of its real
   type (a bug in RN itself, self-consistent because both the read and the write use the same
   wrong key) — so tapping a recipe/list/receipt row's heart still visibly toggles red in RN.
   Swift's `Row.isFavorite` was hardcoded `false` at construction for recipe/list/receipt rows
   (`SearchScreen.swift`, `searchResults`) instead of mirroring RN's wrong-but-consistent
   `favoritesStore.isFavorite(.food, id)` read — fixed to call it for all row types, faithfully
   reproducing RN's bug rather than silently being more "correct" than the source.
2. **`ReceiptDetailScreen`'s macro/micro toggle buttons were missing their trailing chevron.**
   `app/receipt/[id].tsx:268,297` shows a `chevron-up`/`chevron-down` on the right edge of both
   toggle rows (`FoodDetailScreen`/`RecipeDetailScreen` already had this correctly). Added,
   matching the established `Spacer()` + `Image(systemName:)` pattern from the other two screens.
3. **`FoodDetailScreen`'s score ring didn't replay after accepting a swap.** RN's ring-scale
   spring is keyed to `[id]` (`app/food/[id].tsx`), so it re-plays on every `router.replace`.
   Swift's reset lived in `.onAppear` (fires once per sheet presentation) instead of
   `.task(id: currentFoodId)` (fires on every in-place food swap) — moved.
4. **"Added to list" revert was missing its second pop animation.** RN's
   `useAddedToListAnimation.ts`'s `markAdded()` calls `pop()` (a two-step spring) both on add
   *and* again when the 2s revert timer fires. Both `FoodDetailScreen.swift` and
   `RecipeDetailScreen.swift` only animated the add; the revert silently snapped `isAdded`
   back with no pop. Added the matching spring pair to both revert timers.
5. **`RecipeDetailScreen` was missing the "no ingredients" alert.** RN's `generateShoppingList`
   shows `alert("This recipe has no ingredients to add!")` and bails when there's nothing to
   add (`app/recipe/[id].tsx:172-176`); Swift's guard returned silently. Added the alert.
6. **`RecipeDetailScreen`'s shopping-list average score wasn't rounded.** RN always wraps it in
   `Math.round(...)` (`app/recipe/[id].tsx:201-212`); Swift computed a raw `Double` mean in both
   branches of `generateShoppingList` — an inconsistency with `FoodDetailScreen.handleAddToList`
   and `ReceiptDetailScreen.recalculateAndUpdate`, both of which already used
   `JSNumber.roundToInt` correctly. Fixed to match (and to match itself).
7. **`ScanReceiptScreen` was missing the camera-permission alert.** RN's `handleTakePhoto`
   explicitly requests camera permission and shows `alert('Permission needed', 'Camera
   permission is required to take photos.')` on denial before opening the camera
   (`app/scan-receipt.tsx:146-151`); Swift's "Take Photo" button opened the camera sheet
   directly with no permission check, relying silently on the system prompt. Added an
   `AVCaptureDevice.authorizationStatus`/`requestAccess` check with the matching alert.
8. **`ReceiptItemList`'s health-score number wasn't a tap target.** RN wraps the score `Text` in
   its own `TouchableOpacity` with the *same* navigate-to-food handler as the name row
   (`components/ReceiptItemList.tsx:139-153`); Swift's `.onTapGesture` was only on the name/
   nutrition `VStack`. Added the same tap gesture to the score.
9. **`NutritionModal`'s info-circle icons were fully dead.** RN wires each macro/micro row's
   info button to `Alert.alert(name, description)` with distinct educational copy per nutrient
   (`components/NutritionModal.tsx`); Swift rendered the glyph with no `Button`/handler at all.
   Wired all 7 macro rows (copy transcribed verbatim from the RN source) and all micro rows
   (the `description` field was already sitting unused on `MicronutrientTarget`, ported back in
   Phase 4 specifically for this and never wired up until now) to a shared alert.
10. **`NutritionModal`/`SelectShoppingListModal` had backdrop-tap-to-dismiss RN doesn't have.**
    Both RN originals render a plain, non-interactive overlay `View` behind the modal — only
    the explicit close button dismisses it (`NutritionModal.tsx:58-59`,
    `SelectShoppingListModal.tsx:22-23`). Swift had added `.onTapGesture` to both backdrops, a
    small unrequested feature addition. Removed, per rule 3 ("no feature changes" cuts both ways).
11. **`RecipeSearchModal`'s pagination `limit` only reset on `searchQuery` changing.** RN's
    `useEffect` resets it on `[searchQuery, category, maxCalories, minScore, favoritesOnly]`
    (`components/RecipeSearchModal.tsx:42-44`); Swift only had `.onChange(of: searchQuery)`.
    Added the other four.

**One deviation found and left open, not fixed:** `ReceiptItemList.swift`'s shopping-list mode
collapses all items into one untitled section, where RN groups them per-recipe (by each item's
own `recipeName`) plus an "Other Items" section (`components/ReceiptItemList.tsx:194-230`).
This needs a per-item `recipeName` field threaded through `PersistedReceiptItem`/
`ParsedReceiptItem` (currently only `ScanRecord` carries one, at the list level) and touches
`RecipeDetailScreen.generateShoppingList`, `FoodDetailScreen.handleAddToList`, and the
persistence round-trip — a genuine model change, not a one-line fix, and already self-flagged
in `ReceiptItemList.swift`'s own comment since Phase 6. Left as the one standing feature gap
from this pass rather than rushed.

All 11 fixes re-checked with the same brace/paren balance sweep used every phase (no new
mismatches beyond the two pre-existing false positives in `JSSort.swift`/`ReceiptParser.swift`).

**Screenshot review** (`IMG_2457`-`IMG_2466`, all 10 read this phase): Home (kcal badge,
Personalise pill, Health Points ring/card, shopping-list row, carousel spotlight card),
`NutritionModal` (budget card, macro rows with colored dots/bars), Recipes (category chips,
featured-recipe card, empty favorites state), Receipts tab collapsed and expanded (shopping-
list row with basket icon and food-category icons, weekly grouping with `Avg:` badge),
scan-receipt capture view ("How it works" rows), `ReceiptDetailScreen` (confident-match rows
with swap suggestions), `RecipeDetailScreen` (Smart Swaps toggle, Build a Shopping List
stepper, ingredient rows), and Search (popular foods / query results with Nutri-Score badges)
all match the corresponding Swift source's copy text, color tokens, and layout structure as far
as static code reading can confirm — genuine sub-pixel/spacing fidelity still needs a real
device or simulator render, which remains unavailable in every container this port has run in.

---

## Icon mappings

`getIconForCategory` (`State/FoodsStore.swift`) maps `FoodItem.category` substrings to SF
Symbols, mirroring `app/useFoods.ts`'s Ionicons table exactly in condition order and fallback:

| Category substring | Ionicons (RN) | SF Symbol (Swift) | Notes |
|---|---|---|---|
| meat / sausage / poultry | `restaurant-outline` | `fork.knife` | good match |
| fish / seafood | `fish-outline` | `fish` | exact-name match |
| dairy / egg / milk / cheese | `egg-outline` | `carton` | no literal "egg" SF Symbol exists; approximated |
| fruit / vegetable | `leaf-outline` | `leaf` | exact-name match |
| drink / beverage / water | `water-outline` | `drop` | good match |
| sweet / pastry / sugar | `ice-cream-outline` | `birthday.cake` | no SF ice-cream symbol; approximated |
| cereal / grain / bread / pantry | `nutrition-outline` | `basket` | no close SF equivalent for RN's grain-stalk glyph; approximated |
| *(fallback)* | `fast-food-outline` | `takeoutbag.and.cup.and.straw` | good match |

The egg/dairy and cereal/grain rows are the two already-flagged approximations from Phase 4 —
still standing, since no closer SF Symbol exists for either RN glyph. **Not verified against a
live SF Symbols catalog** (no Xcode in this container) — check every name before shipping.

Every other Ionicons/Feather/`expo-symbols` name used directly in the RN source (as opposed to
via `getIconForCategory`) was cross-checked this phase against its Swift `systemName:` call
site. All resolve to the semantically-closest SF Symbol, correctly distinguishing Ionicons'
`-outline` (unfilled) suffix from its absence (filled) by using SF's bare-name-vs-`.fill`-suffix
convention consistently — e.g. `checkmark-circle-outline`→never used bare, `checkmark-circle`
(filled)→`checkmark.circle.fill`; `basket-outline`→`basket`; `trophy-outline`/`trophy`→
`trophy`/`trophy.fill`; `heart-outline`/`heart`→`heart`/`heart.fill`. Notable pairs: `options-
outline`→`slider.horizontal.3` (Apple's own HIG-recommended replacement), `ribbon-outline`→
`rosette`, `people-outline`→`person.2`, `open-outline`→`arrow.up.forward.square`, `speedometer-
outline`→`speedometer`, `flask-outline`→`testtube.2`, `pie-chart-outline`→`chart.pie`. The
`ClassicTabLayout` tab bar (`RootView.swift`) matches `app/(tabs)/_layout.tsx`'s own
`ClassicTabLayout` branch exactly — `house.fill`/`fork.knife`/`list.bullet.rectangle`/
`magnifyingglass`, statically (RN's classic branch, unlike its `NativeTabs`/Liquid-Glass
branch, does not swap to a `-outline`/`.fill` pair on selection either). `app/settings.tsx`
already specifies literal SF Symbol names via `expo-symbols`' `SymbolView` (with an Ionicons
fallback that's moot at this port's iOS 16.4 minimum), so every Settings row icon is an exact
1:1 copy, not a mapping.

`FoodIcon`'s 85 OpenMoji SVGs are still not rendered at all (Phase 4's `FoodIcon.swift` always
takes the fallback path above) — pre-rasterising them at build time is unstarted, and needs a
build step this container can't run.
