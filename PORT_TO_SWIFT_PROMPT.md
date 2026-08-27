# Task: Port Smart Swaps from Expo / React Native to a native Swift iOS app

You are porting an existing, working Expo SDK 54 / React Native 0.81 app (`smart-swaps-mobile`) to a pure native iOS app written in Swift + SwiftUI. This is a **1:1 translation**, not a redesign and not a rewrite. Every screen must look the same, every interaction must feel the same, and every algorithm must produce **bit-identical output** for the same input.

The React Native source is the specification. When the RN code and this brief disagree, **the RN code wins**. Read the actual file before porting it — never port from memory or from this summary alone.

---

## Absolute rules

1. **No behavioural drift.** If a function returns `0.7231` for a given input in TypeScript, the Swift version returns `0.7231`. Same rounding, same tie-breaking, same sort stability, same clamping, same `null` vs `0` distinctions.
2. **No visual drift.** Every color, corner radius, font size, font weight, letter spacing, padding, margin, shadow offset/opacity/radius, blur intensity, and animation curve/duration is copied exactly from the RN source. Do not "improve" spacing or substitute a system component whose metrics differ.
3. **No feature changes.** Do not add features, do not remove features, do not fix bugs you notice. If you find a bug, port the bug and record it in `PORTING_NOTES.md` under "Bugs faithfully reproduced".
4. **No placeholders.** No `// TODO`, no stubbed functions, no "simplified for now". Every ported file is complete.
5. **Ask before deviating.** If an exact port is genuinely impossible on the platform, stop and ask rather than silently approximating.

---

## Target stack

- **Language:** Swift 5.9+ (or newer), strict concurrency where practical
- **UI:** SwiftUI, with UIKit bridging (`UIViewRepresentable`) only where SwiftUI cannot reproduce the exact behaviour
- **Minimum iOS:** 16.4 (matches `app.json` → `expo-build-properties.ios.deploymentTarget`)
- **Persistence:** SQLite via GRDB or SQLite.swift for the bundled DB; `UserDefaults` (or a JSON-file store) for the AsyncStorage replacement
- **No third-party UI frameworks.** No React-in-Swift shims, no cross-platform layers, no WebViews for UI.
- **Package manager:** SPM only

---

## Source architecture you are porting

Total: roughly 13,000 lines of TS/TSX across `app/`, `components/`, `styles.ts`, `SearchScreen.tsx`, and `modules/`.

### Navigation (expo-router → SwiftUI)

`app/_layout.tsx` wraps everything in four context providers and a `Stack` with transparent, blurred headers. `app/(tabs)/_layout.tsx` branches: if `isLiquidGlassAvailable()` it renders `NativeTabs` with SF Symbols; otherwise a classic `Tabs` bar with a `BlurView` background.

| Route | File | Presentation |
|---|---|---|
| Home / Today | `app/(tabs)/index.tsx` (400 ln) | tab |
| Recipes | `app/(tabs)/recipes.tsx` (310 ln) | tab |
| Receipts | `app/(tabs)/receipts.tsx` (467 ln) | tab |
| Search | `app/(tabs)/search.tsx` → `SearchScreen.tsx` (763 ln, `mode="foods"`) | tab |
| Settings | `app/settings.tsx` (808 ln) | pushed, hidden from tab bar (`href: null`) |
| Food detail | `app/food/[id].tsx` (716 ln) | **modal** sheet |
| Recipe detail | `app/recipe/[id].tsx` (851 ln) | **modal** sheet |
| Receipt detail | `app/receipt/[id].tsx` (500 ln) | pushed |
| Scan receipt | `app/scan-receipt.tsx` (465 ln) | pushed |

Tab bar: Home (`house` / `house.fill`), Recipes (`fork.knife`), Receipts (`list.bullet.rectangle` / `.fill`), Search (`magnifyingglass`). On iOS 26+ use the native Liquid Glass tab bar; below that, a `UIBlurEffect` bar tinted `COLORS.primaryGreen` when active, `COLORS.textMuted` when inactive, labels at 10pt.

Modal routes (`food/[id]`, `recipe/[id]`) must present as iOS sheets, matching the RN `presentation: 'modal'` behaviour including swipe-to-dismiss.

### Contexts → observable app state

Port each to an `@Observable` / `ObservableObject` injected via `@Environment`, preserving load order, default values, and hydration timing (each reads from AsyncStorage on mount and renders defaults until loaded — reproduce that, don't block the UI on it).

- `ProfileContext.tsx` (163 ln) — key `@smart_swaps_profile`, includes `dietaryPreference: DietaryPreference[]` and derived `targetCalories`
- `FavoritesContext.tsx` (78 ln) — key `@smart_swaps_favorites`
- `SettingsContext.tsx` (70 ln) — key `@smart_swaps_settings`
- `InventoryContext.tsx` (70 ln) — `shoppingLists`, `scans`

### Persistent storage — keep the exact keys and JSON shapes

| Key | Source |
|---|---|
| `@smart_swaps_profile` | `ProfileContext` |
| `@smart_swaps_favorites` | `FavoritesContext` |
| `@smart_swaps_settings` | `SettingsContext` |
| `@smart_swaps_scans` | `services/storage.ts` |
| `@smart_swaps_interactions` | `services/storage.ts` |
| `@smart_swaps_overrides` | `services/overrideStore.ts` |
| `swap_personal_preferences_v1` | `engine/personalSwapPreferences.ts` |
| `swap_training_log_v1` | `engine/swapTrainingLog.ts` (capped at `MAX_ROWS`) |
| `match_diagnostic_log_v1` | `services/matchLog.ts` (capped at `MAX_ROWS`) |

`StorageService` writes `ScanRecord` objects — new scans are **prepended** (`[newScan, ...existing]`). Preserve that ordering, the `Omit<ScanRecord, 'interactions'>` → `interactions: []` initialization, and the silent `catch` on every failure (log, never throw).

### Database

`assets/smartswaps.db` (7.6 MB SQLite) is bundled and, per `services/database.ts`, copied out of the bundle into the app's SQLite directory on first access — **deleting and re-copying every launch** in the current code. Reproduce that behaviour exactly, including the overwrite (note it in `PORTING_NOTES.md` as intentional-per-source).

Tables and the exact column → model mapping are in `DatabaseService.mapFoodRow`:
- `foods` — flat columns for macros, plus a `micros` **JSON string column** that must be parsed into the `micros` dictionary (21 keys, see `app/types.ts`)
- `recipes` — `steps` is a JSON string column
- `recipe_ingredients` — fetched in one query `ORDER BY recipe_id, sort_order`, then grouped in memory (do not switch to N+1 queries or to a SQL JOIN that changes ordering)
- `icon_library` — `icon_key` → `svg_content` (raw SVG strings)

### The engine — the highest-risk part of this port

`app/engine/` is pure, deterministic TypeScript with no UI dependencies. Port it **first**, before any UI, and prove equivalence before moving on.

- `swapAlgorithm.ts` (447 ln) — `isLiquid`, `isRawIngredient`, `evaluateSwap`, `findBestSwaps`, `findBestSwapsPersonalized`, `swapSuppressionReason`
- `receiptParser.ts` (755 ln) — German receipt OCR parsing: `normalize`, `asciiFold`, `matchFoodToOcrText`, `isLikelyProductLine`, `parseReceiptLine`, `parseReceipt`. Heavy regex and fuzzy-scoring; **the single most fragile file in the port**
- `resolveProduct.ts` (230 ln) — `resolveProductLine`, `bridgeOffToBls`, `enrichWithOff`, plus the confidence constants (`OFF_UPGRADE_THRESHOLD = 0.45`, `OFF_BRIDGE_MIN_CONFIDENCE = 0.6`, `EXACT_LOOKUP_CONFIDENCE = 0.99`, `BRAND_DICT_CONFIDENCE = 0.95`)
- `swapGbm.ts` (192 ln) + `swapGbm.data.json` (133 KB) — a gradient-boosted tree model evaluated in-process. Port the tree traversal exactly; `null` features are meaningful, not zero
- `swapRanker.ts` (153 ln) — logistic scorer, `combineWithExistingScore`
- `foodEmbeddings.ts` + `foodEmbeddings.data.json` (3.8 MB) — cosine similarity over precomputed vectors. Consider a binary/`mmap`-friendly format for load time, but the numeric results must be identical
- `foodAttributes.ts` + `foodAttributes.data.json` (215 KB)
- `foodVectors.ts`, `foodIndex.ts`, `dietaryFilter.ts`, `recipeSwapAlgorithm.ts`, `smartSwaps.ts`, `brandDict.ts`, `exactLookup.ts`, `knownNonMatches.ts`, `germanAbbreviations.ts`, `micronutrients.ts`, `overrideKey.ts`, `personalSwapPreferences.ts`, `swapTrainingLog.ts`
- Data files in `app/data/`: `exactLookup.json`, `verifiedBrandMap.json`, `knownNonMatches.json` — ship as-is, do not restructure

**JS/Swift semantic traps to handle deliberately:**
- JS `Array.prototype.sort` is stable and compares differently from Swift's `sort` (which is *not* guaranteed stable) — implement a stable sort and replicate the exact comparator, including how it handles equal keys and `NaN`
- `Math.round` rounds half **up** (`.5` → toward +∞); Swift's `rounded()` rounds half **away from zero**. These differ for negatives — use the JS rule
- JS numbers are all `Double`. Do not introduce `Int` arithmetic where TS did floating-point
- `undefined` vs `null` vs `0` distinctions in the scoring code are load-bearing — model with `Optional`, never a sentinel
- String normalization: `normalize()` / `asciiFold()` must produce byte-identical output for German umlauts, ß, and OFF's `en:`-prefixed tags. Port the regexes literally (`NSRegularExpression` with the same patterns; watch Unicode-property and case-folding differences)
- `Set` and `Map` iteration order in JS is insertion order — Swift `Set`/`Dictionary` are unordered. Anywhere iteration order affects the result (e.g. `candidatesMap` on the Home screen), use an ordered structure

### Networking

`services/offClient.ts` (120 ln) — Open Food Facts search-a-licious client. Preserve: endpoint `https://search.openfoodfacts.org/search`, the descriptive `User-Agent`, `DEFAULT_TIMEOUT_MS = 3000`, `MAX_ATTEMPTS = 2`, `RETRY_DELAY_MS = 400`, retryable statuses `{429, 502, 503, 504}` only, and the contract that **any** failure resolves to `nil` and never throws. 4xx "no such product" is never retried.

### OCR — already native, reuse it

`modules/native-ocr/ios/NativeOcrModule.swift` is already Swift using Apple's Vision framework. **Lift this file almost verbatim**, stripping only the `ExpoModulesCore` wrapper (`Module`, `AsyncFunction`, `Promise`) and replacing it with an `async throws` Swift API. Keep exactly:
- `recognitionLevel = .accurate`, `usesLanguageCorrection = true`
- the observation sort: by `boundingBox.midY` descending, with a `0.01` epsilon, then `minX` ascending
- the result shape `{ text, blocks: [{ text, lines: [{ text }] }] }` (all lines in one block) — downstream `receiptParser` consumes it as `blocks.flatMap { $0.lines.map(\.text) }`
- the `loadImage` fallback chain (file URL → path → other URL scheme)

The Android/Kotlin side (`NativeOcrModule.kt`) is out of scope. `tesseract.js` appears in `package.json` but is **not imported anywhere** in `app/` or `components/` — do not port it.

### Component library → SwiftUI views

Port each 1:1, keeping the file name and the prop signature shape:

| Component | Notes |
|---|---|
| `SwapComparisonCard.tsx` (408 ln) | the core swap UI |
| `NutritionModal.tsx` (405 ln) | uses `expo-blur` |
| `RecipeCard.tsx` (364 ln) | |
| `ReceiptItemList.tsx` (351 ln) | uses `expo-haptics` → `UIImpactFeedbackGenerator`; match the exact haptic style and trigger points |
| `RecipeSearchModal.tsx` (346 ln) | |
| `GlassHeader.tsx` (281 ln) | see below — hardest visual port |
| `SelectShoppingListModal.tsx` (201 ln) | |
| `SpotlightCard.tsx` (157 ln) | |
| `Header.tsx` (154 ln) | |
| `CoverFlowCarousel.tsx` (124 ln) | see below |
| `RecommendedCard.tsx` (115 ln) | |
| `HealthPointsCard.tsx` (94 ln) | |
| `NutrientRow.tsx` (81 ln) | |
| `CircularScoreRing.tsx` (78 ln) | SVG ring; `size=40`, `strokeWidth=4` defaults, `strokeDashoffset` math, color thresholds ≥70 green / ≥40 yellow / else red, with matching light background colors |
| `LiquidSlider.tsx` (72 ln) | `@react-native-community/slider`; thumb is `#FFFFFF` on iOS, track `primaryGreen` / `border`, `step: 1`, label shows `{max}+ {unit}` at max |
| `SearchModal.tsx` (24 ln) | |
| `FoodIcon.tsx` (24 ln) | see below |

**`GlassHeader.tsx` — progressive blur.** This is a `MaskedView` masking a `BlurView` (`intensity={12}`, `tint="systemChromeMaterial"`) with a native vertical `LinearGradient`. The gradient uses `FADE_EXTENSION = 44`px, `FADE_STEPS = 10`, and a quadratic ease-out alpha ramp `alpha = (1 - t)²` with `t = (i + 1) / FADE_STEPS`, alphas formatted to 3 decimals, final stop `transparent`. Locations are `[0, solidStop, ...fadeLocations]` where `solidStop = headerHeight / (headerHeight + 44)`. Reproduce with a `UIVisualEffectView` (`.systemChromeMaterial`) plus a `CAGradientLayer` mask using the **same** stop values — do not substitute a plain `.ultraThinMaterial`, the falloff will be visibly different. Also port `LargeTitle`, `HEADER_CONTENT_HEIGHT`, and the `scrollY`-driven title transition.

**`CoverFlowCarousel.tsx` — infinite looping carousel.** `ITEM_WIDTH = screenWidth * 0.78`, `ITEM_SPACING = (screenWidth - ITEM_WIDTH) / 2`. Data is tripled (`[...data, ...data, ...data]`) and the scroll position silently jumps back to the middle set in `onMomentumScrollEnd` when the index leaves it. Per-item interpolation over `[(i-1)·W, i·W, (i+1)·W]`: scale `0.85 → 1 → 0.85`, opacity `0.5 → 1 → 0.5`, both clamped. Uses `snapToInterval={ITEM_WIDTH}` and `decelerationRate="fast"` — match the snap and deceleration feel, not just the geometry.

**`FoodIcon.tsx` — SVG rendering.** Icons are OpenMoji SVG strings stored **in the database** (`icon_library.svg_content`), rendered via `SvgXml`. iOS has no built-in SVG renderer, so pick one and justify it in `PORTING_NOTES.md`: pre-rasterize at build time into an asset catalog (fastest, loses scalability), parse to `CAShapeLayer` paths, or add a minimal SVG library. Fallback path when `icon_key` is null or the SVG fails: the Ionicons glyph from `getIconForCategory(food.category)` — map each Ionicons name used to its closest SF Symbol and list the mapping in the notes.

**Icons generally:** `@expo/vector-icons` (Ionicons, Feather) and `expo-symbols` (SF Symbols) are both used. SF Symbols map directly. For Ionicons/Feather, produce an explicit name→SF Symbol mapping table, keeping optical size and weight as close as possible; where no SF Symbol matches, bundle the original glyph.

### Design tokens

Port `styles.ts` verbatim into a Swift `Colors` enum and a set of view modifiers. All 40+ colors, exact hex. The `globalStyles.card` shadow is iOS-specific: `shadowColor: '#0F1D11'`, `offset (0, 6)`, `opacity 0.04`, `radius 12`, `borderRadius: 24`, `padding: 20`, `marginBottom: 16`. `scrollContent` uses `paddingHorizontal: 20`, `paddingBottom: 100` (clears the tab bar), `paddingTop: 10`. Typography: `title` 32/800/`-0.5` tracking, `sectionTitle` 20/700, `subtitle` 14 with `lineHeight: 20`, `bodyText` 14/20.

**Font:** the tab bar specifies `fontFamily: "Nunito_500Medium"` via `expo-font`. Bundle the same Nunito files and register them; do not substitute SF Pro. Note that RN `fontWeight: '800'` maps to the font's ExtraBold face — verify each weight resolves to the same physical face.

**Layout:** RN uses flexbox with `flex: 1` defaults and `alignItems: 'stretch'`. SwiftUI's stack layout differs in how it distributes leftover space and how text wraps. Where a screen's layout depends on flex behaviour, verify against a screenshot rather than assuming the SwiftUI equivalent matches.

### Reference screenshots

`IMG_2457.PNG` … `IMG_2466.PNG` at the repo root are screenshots of the running RN app. Use them as the visual acceptance criteria — a screen is done when a side-by-side with the corresponding screenshot shows no perceptible difference in spacing, weight, color, or hierarchy.

---

## Out of scope

Do not port: `scripts/`, `scratch/`, `colab/`, `landing/`, `bls_data/`, `bls.zip`, `precompute-food-embeddings.js`, `foods.json`, `recipes.json`, `swap_training_rows.json`, or the Android/Kotlin OCR module. These are build-time tooling and source data already baked into `smartswaps.db` and the `.data.json` assets. Leave the RN project untouched — the Swift app goes in a new directory.

---

## How to work

Work in phases. **Do not start a phase until the previous one is verified.** Commit at the end of each phase.

**Phase 0 — Inventory.** Read every file in `app/`, `components/`, `styles.ts`, and `SearchScreen.tsx`. Produce `PORTING_INVENTORY.md`: every screen, component, engine function, storage key, and data asset, with its target Swift file. Flag anything you're unsure about. **Stop and show me this before writing Swift.**

**Phase 1 — Project skeleton.** Xcode project, SPM deps, bundled `smartswaps.db` and the three `.data.json` assets, Nunito fonts, `Colors`/`GlobalStyles`, `Info.plist` (photo library permission for `expo-image-picker`'s role in `scan-receipt`). Builds and launches to an empty tab bar.

**Phase 2 — Data layer.** `types.ts` → Swift models (`Codable`, matching JSON keys exactly). Database service with the copy-from-bundle behaviour. Storage service with the exact keys. Contexts → observable state.

**Phase 3 — Engine.** All of `app/engine/`, pure Swift, no UI. **This phase requires proof:**
- Port `scripts/regression.cases.ts`, `scripts/baseline.cases.ts`, `scripts/ground_truth.json`, and `scripts/off-eval.cases.ts` into an XCTest suite.
- `scripts/baseline.snapshot.json` is the frozen expected output — your Swift engine must reproduce it exactly.
- Additionally: run the TS engine over a few thousand generated inputs (`npx tsx`), dump results to JSON, and assert the Swift port matches within `1e-9` for floats and exactly for everything else. Do this for `evaluateSwap`, `findBestSwaps`, `predictSwapQualityGbm`, `embeddingCosine`, `normalize`, `asciiFold`, and `parseReceipt`.
- **Do not proceed to UI until this suite is green.**

**Phase 4 — Shared components.** All of `components/`, each with a SwiftUI preview reproducing its appearance in isolation.

**Phase 5 — Screens.** One at a time, simplest first: Search → Recipes → Receipts → Home → Settings → detail modals → scan flow. After each, compare against the reference screenshot and report the diff.

**Phase 6 — Integration.** Navigation, modal presentation, deep links, haptics, the full scan → parse → resolve → swap → save flow end to end.

**Phase 7 — Verification pass.** Walk every screen and every user action in both apps side by side. Produce `PORTING_NOTES.md`: platform deviations and why, bugs faithfully reproduced, icon mappings, and anything left uncertain.

---

## Reporting

At the end of each phase, tell me: what you ported, what tests prove it's correct, what you had to approximate and why, and what you're uncertain about. Short and specific — no summaries of things that went fine.

If you hit something where an exact port is impossible, **stop and ask**. A question is much cheaper than a silent approximation buried in a scoring function.
