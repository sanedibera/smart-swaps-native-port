/**
 * Runs the LIVE TypeScript engine and dumps its output, so the Swift port can be diffed
 * against the real thing rather than against a reimplementation that would drift.
 *
 * Deterministic: every sample is drawn with a seeded RNG, so two runs produce byte-
 * identical files and a diff means the engine changed, not the sampler.
 */
import * as fs from 'fs';
import { loadFoods } from '../../scripts/lib/loadFoods';
import { normalize, asciiFold, parseReceiptLine, matchFoodToOcrText } from '../../app/engine/receiptParser';
import { buildFoodIndex } from '../../app/engine/foodIndex';
import { evaluateSwap, findBestSwaps, isLiquid, isRawIngredient, swapSuppressionReason } from '../../app/engine/swapAlgorithm';
import { extractGbmFeatures, predictSwapQualityGbm } from '../../app/engine/swapGbm';
import { embeddingCosine } from '../../app/engine/foodEmbeddings';
import { getAttributes } from '../../app/engine/foodAttributes';
import { isAllowedForDiet, containsMeatOrFish, containsAnimalProduct, isPlantAlternative } from '../../app/engine/dietaryFilter';
import { getProduceGroup, isProduce } from '../../app/engine/produceGroups';
import { getCulinaryFunction, culinaryVeto, getDishFlavour } from '../../app/engine/culinaryFilter';
import { matchBrandDict } from '../../app/engine/brandDict';
import { matchExactLookup } from '../../app/engine/exactLookup';
import { isKnownNonMatch } from '../../app/engine/knownNonMatches';
import { normalizeOverrideKey } from '../../app/engine/overrideKey';
import { expandGermanAbbreviations } from '../../app/engine/germanAbbreviations';
import { REGRESSION_CASES } from '../../scripts/regression.cases';
import { OFF_EVAL_CASES } from '../../scripts/off-eval.cases';
import { BASELINE_CASES } from '../../scripts/baseline.cases';

function mulberry32(seed: number) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const foods = loadFoods();
const out: any = {};

// ---- 1. String normalisation, over a corpus that is deliberately umlaut-heavy --------
const stringCorpus: string[] = [];
for (const f of foods) {
  stringCorpus.push(f.name);
  if (f.name_de) stringCorpus.push(f.name_de);
}
for (const c of REGRESSION_CASES) stringCorpus.push(c.line);
for (const c of OFF_EVAL_CASES as any[]) stringCorpus.push(c.query);
for (const c of BASELINE_CASES as any[]) stringCorpus.push(c.line);
// Adversarial extras aimed squarely at the \b and \w differences.
stringCorpus.push(
  'äpfel', 'ämilch', 'Käse Brötchen 500g', 'Grieß', 'Weiße Bohnen', 'Crème fraîche',
  'naïve café', 'ÄÖÜ ßß', 'MOZ2./BUEA MIN', '  leading and trailing  ', 'a\tb\nc',
  'straße', 'strasse', 'Müllerstraße 141', 'é combining', 'é precomposed',
  'ﬀ ligature', '４００ｇ fullwidth', '', ' ', '...', '3,5% Fett', 'Vollmilch 3.5%',
);
out.strings = stringCorpus.map(s => ({ s, n: normalize(s), a: asciiFold(s) }));

// ---- 2. Per-food scalars: every food, no sampling -----------------------------------
out.perFood = foods.map(f => ({
  id: f.id,
  liq: isLiquid(f) ? 1 : 0,
  rawIng: isRawIngredient(f) ? 1 : 0,
  supp: swapSuppressionReason(f),
  prod: isProduce(f) ? 1 : 0,
  pgroup: getProduceGroup(f),
  cfn: getCulinaryFunction(f),
  meat: containsMeatOrFish(f) ? 1 : 0,
  animal: containsAnimalProduct(f) ? 1 : 0,
  plant: isPlantAlternative(f) ? 1 : 0,
  vgt: isAllowedForDiet(f, ['Vegetarian']) ? 1 : 0,
  vgn: isAllowedForDiet(f, ['Vegan']) ? 1 : 0,
  bal: isAllowedForDiet(f, ['Balanced']) ? 1 : 0,
  attrs: (() => {
    const a = getAttributes(f.id);
    return a ? [...a.sensory, a.culinaryRole, a.prepState, a.glycemicLoad, a.satiety,
                a.caffeine ? 1 : 0, a.alcohol ? 1 : 0, a.timeOfDayMask] : null;
  })(),
}));

// ---- 3. Pairwise: evaluateSwap, GBM features + probability, cosine ------------------
const rngPairs = mulberry32(12345);
const pairs: [number, number][] = [];
for (let i = 0; i < 6000; i++) {
  pairs.push([Math.floor(rngPairs() * foods.length), Math.floor(rngPairs() * foods.length)]);
}
out.pairs = pairs.map(([i, j]) => {
  const a = foods[i], b = foods[j];
  const cos = embeddingCosine(a.id, b.id);
  const lm = isLiquid(a) !== isLiquid(b) ? 1 : 0;
  const rm = isRawIngredient(a) !== isRawIngredient(b) ? 1 : 0;
  const feats = extractGbmFeatures(a, b, cos, lm as 0 | 1, rm as 0 | 1);
  return {
    a: a.id, b: b.id,
    cos, ev: evaluateSwap(a, b),
    f: feats, p: predictSwapQualityGbm(feats),
    veto: culinaryVeto(a, b, 'SAVOURY'),
    vetoSweet: culinaryVeto(a, b, 'SWEET'),
  };
});

// ---- 4. findBestSwaps: the whole pipeline, top-5 per source -------------------------
const rngSrc = mulberry32(777);
const srcIdx = new Set<number>();
while (srcIdx.size < 500) srcIdx.add(Math.floor(rngSrc() * foods.length));
const DIETS: string[][] = [['Balanced'], ['Vegetarian'], ['Vegan']];
out.swaps = [];
for (const i of srcIdx) {
  const f = foods[i];
  for (let d = 0; d < DIETS.length; d++) {
    const r = findBestSwaps(f, foods, 5, DIETS[d]);
    out.swaps.push({ id: f.id, d, top: r.map(x => ({ c: x.candidate.id, s: x.score })) });
  }
  // Also exercise the recipe screen's policy overrides.
  const rp = findBestSwaps(f, foods, 5, ['Balanced'], { allowWholeFoods: true, minImprovement: 0 });
  out.swaps.push({ id: f.id, d: 3, top: rp.map(x => ({ c: x.candidate.id, s: x.score })) });
}

// ---- 5. Dish flavour over real recipe-shaped ingredient sets ------------------------
const rngDish = mulberry32(31337);
out.dishes = [];
for (let k = 0; k < 300; k++) {
  const n = 3 + Math.floor(rngDish() * 10);
  const ids: string[] = [];
  for (let m = 0; m < n; m++) ids.push(foods[Math.floor(rngDish() * foods.length)].id);
  const byId = new Map(foods.map(f => [f.id, f]));
  out.dishes.push({ ids, flavour: getDishFlavour(ids.map(id => byId.get(id)!)) });
}

// ---- 6. Dictionary tiers and key normalisation --------------------------------------
const lineCorpus = Array.from(new Set([
  ...REGRESSION_CASES.map(c => c.line),
  ...(OFF_EVAL_CASES as any[]).map(c => c.query),
  ...(BASELINE_CASES as any[]).map(c => c.line),
]));
out.lines = lineCorpus.map(l => ({
  l,
  ok: normalizeOverrideKey(l),
  brand: matchBrandDict(l),
  exact: matchExactLookup(l),
  knm: isKnownNonMatch(l) ? 1 : 0,
  ger: expandGermanAbbreviations(l),
}));

// ---- 7. The retrieval stage end to end ---------------------------------------------
const indexData = buildFoodIndex(foods);
out.indexStats = {
  index: indexData.index.size,
  stem: indexData.stemIndex!.size,
  shingle: indexData.shingleIndex!.size,
  fourGram: indexData.fourGramIndex!.size,
};
out.parse = lineCorpus.map(l => {
  const p = parseReceiptLine(l, foods, indexData);
  const m = matchFoodToOcrText(l, foods, indexData);
  // Explicit nesting rather than undefined-vs-null: JSON.stringify DROPS undefined, and
  // a Swift Decodable cannot then tell "TS returned null" from "TS returned an item whose
  // matchedFood is null" - two genuinely different outcomes of parseReceiptLine.
  return {
    l,
    p: p === null ? null : { f: p.matchedFood ? p.matchedFood.id : null, c: p.confidence },
    mf: m ? m.food.id : null,
    mc: m ? m.confidence : null,
    mh: m ? (m.hasStrongHit ? 1 : 0) : null,
  };
});

fs.writeFileSync(process.argv[2], JSON.stringify(out));
console.log('strings', out.strings.length, '| perFood', out.perFood.length,
            '| pairs', out.pairs.length, '| swaps', out.swaps.length,
            '| dishes', out.dishes.length, '| lines', out.lines.length,
            '| parse', out.parse.length);
console.log('index sizes', JSON.stringify(out.indexStats));
