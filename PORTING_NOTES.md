# PORTING_NOTES.md

Running record of deviations, reproduced bugs and measurements. Started at Phase 3 rather
than Phase 7 so nothing is reconstructed from memory later. **Phases 0-3 complete; phases
4-7 (UI) not started**, so the icon-mapping and visual-deviation sections are stubs.

---

## Status

| Phase | State |
|---|---|
| 0 Inventory | done — `PORTING_INVENTORY.md` |
| 1 Skeleton | **partial** — SPM package, resources, compat layer done. **Xcode app target not yet created**, so "launches to an empty tab bar" is not yet demonstrated. |
| 2 Data layer | done, verified row-for-row |
| 3 Engine | **done, gate green** — 18 tests, 0 failures |
| 4-7 | not started |

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

---

## Still uncertain / open

- **`sort(() => 0.5 - Math.random())`** (Home carousel filler, SearchScreen placeholder).
  An inconsistent comparator is not a specification and `Math.random()` is unseeded, so
  byte-identical output is impossible in principle. Plan: same algorithm via `JSSort`, same
  non-uniform bias, different sequence. Both sites are purely decorative. **Not yet reached.**
- **Case-insensitive matching (`i` flag).** ICU does full Unicode case folding, JS's
  non-unicode mode does simple folding; `ß`/`ss` could in principle differ. No divergence
  appeared across 14,632 strings and 168 parse lines, but it is unproven in general.
- **Xcode app target does not exist yet.** Phase 1's "launches to an empty tab bar" gate is
  outstanding; there is no `xcodegen` on this machine, so the `.pbxproj` will be generated
  by a committed script rather than hand-edited across phases.

---

## Icon mappings

*(Phase 4 — not started. `FoodIcon`'s 85 OpenMoji SVGs will be pre-rasterised at build
time; the Ionicons/Feather → SF Symbol table lands here, with the two glyphs that have no
close SF equivalent — `egg-outline`, `nutrition-outline` — bundled as originals.)*
