// Emits V8's Array.prototype.sort output for cases built around the exact comparator
// shape used by matchFoodToOcrText - the one that is NOT a total order.
import { writeFileSync } from 'node:fs';

function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const cases = [];
// Sizes chosen to straddle every TimSort path: below minRun, single run, multi-run with
// merges, and well past the galloping threshold.
const sizes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 21, 22, 31, 32, 33, 63, 64, 65, 66, 100, 127, 128, 129, 200, 400, 1000, 2000];
let seed = 1;
for (const n of sizes) {
  for (let rep = 0; rep < 40; rep++) {
    const rng = mulberry32(seed++);
    const items = [];
    for (let i = 0; i < n; i++) {
      // Confidences deliberately clustered so the +/-0.03 band is hit constantly.
      const bucket = Math.floor(rng() * 6) * 0.02;
      items.push({
        id: i,
        confidence: +(bucket + rng() * 0.05).toFixed(6),
        unmatchedCount: Math.floor(rng() * 5),
      });
    }
    const sorted = [...items].sort((a, b) => {
      if (Math.abs(b.confidence - a.confidence) <= 0.03) {
        return a.unmatchedCount - b.unmatchedCount;
      }
      return b.confidence - a.confidence;
    });
    cases.push({ kind: 'receiptBand', items, expected: sorted.map(x => x.id) });
  }
}

// The findBestSwaps comparator: `b.score - a.score || handScore(b) - handScore(a)`,
// including exact score ties (common for near-duplicate BLS preparation variants).
for (const n of sizes) {
  for (let rep = 0; rep < 25; rep++) {
    const rng = mulberry32(seed++);
    const items = [];
    for (let i = 0; i < n; i++) {
      items.push({
        id: i,
        score: +(Math.floor(rng() * 8) / 8).toFixed(6),   // heavy tie rate
        hand: Math.floor(rng() * 1000) - 500,
      });
    }
    const sorted = [...items].sort((a, b) => (b.score - a.score) || (b.hand - a.hand));
    cases.push({ kind: 'swapRank', items, expected: sorted.map(x => x.id) });
  }
}

// Plain descending-by-length with ties, i.e. brandDict's key sort.
for (const n of [10, 50, 200, 978]) {
  for (let rep = 0; rep < 6; rep++) {
    const rng = mulberry32(seed++);
    const items = [];
    for (let i = 0; i < n; i++) items.push({ id: i, len: 1 + Math.floor(rng() * 20) });
    const sorted = [...items].sort((a, b) => b.len - a.len);
    cases.push({ kind: 'byLength', items, expected: sorted.map(x => x.id) });
  }
}

writeFileSync(process.argv[2], JSON.stringify({ cases }));
console.log(`wrote ${cases.length} sort cases`);
