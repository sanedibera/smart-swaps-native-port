/**
 * Exports the project's own regression fixtures to JSON so the Swift suite runs the SAME
 * cases, not a retyped subset. baseline.snapshot.json is copied through untouched here -
 * this tool never regenerates it. Regenerating IS sometimes correct (the snapshot is a
 * frozen artefact of one engine revision, and the working-tree engine moves), but that is
 * a decision for whoever changes the engine, made explicitly with
 * `npx tsx scripts/baseline-eval.ts --save scripts/baseline.snapshot.json` - not something
 * this export step should do silently as a side effect of copying fixtures.
 */
import * as fs from 'fs';
import * as path from 'path';
import { REGRESSION_CASES } from '../../scripts/regression.cases';
import { BASELINE_CASES } from '../../scripts/baseline.cases';

const dst = process.argv[2];
fs.writeFileSync(path.join(dst, 'regression-cases.json'),
  JSON.stringify(REGRESSION_CASES.map(c => ({ line: c.line, expected: c.expected ?? null, note: c.note ?? null }))));
fs.writeFileSync(path.join(dst, 'baseline-cases.json'),
  JSON.stringify((BASELINE_CASES as any[]).map(c => ({ line: c.line, expected: c.expected ?? null, bucket: c.bucket }))));
fs.copyFileSync(path.join(__dirname, '..', '..', 'scripts', 'baseline.snapshot.json'),
  path.join(dst, 'baseline-snapshot.json'));
console.log('regression', REGRESSION_CASES.length, '| baseline', (BASELINE_CASES as any[]).length);
