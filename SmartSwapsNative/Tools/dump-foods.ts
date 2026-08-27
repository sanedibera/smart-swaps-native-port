/**
 * Dumps every food exactly as the TS app sees it, in the order the app receives it, so
 * the Swift data layer can be diffed row-for-row rather than spot-checked.
 *
 * Uses scripts/lib/loadFoods.ts - the same read path the offline pipeline uses, and
 * verified in PORTING_INVENTORY.md §3.2 to be identical to app/services/database.ts.
 */
import * as fs from 'fs';
import { loadFoods } from '../../scripts/lib/loadFoods';

const foods = loadFoods();
const rows = foods.map(f => ({
  i: f.id, n: f.name, d: f.name_de ?? null, c: f.category, s: f.swiss_category,
  h: f.health_score, g: f.nutri_grade ?? null, v: f.nova_group ?? null,
  k: f.icon_key ?? null,
  u: [f.nutrients_per_100.kcal, f.nutrients_per_100.protein_g, f.nutrients_per_100.carbs_g,
      f.nutrients_per_100.sugars_g, f.nutrients_per_100.fat_g,
      f.nutrients_per_100.saturated_fat_g, f.nutrients_per_100.fiber_g,
      f.nutrients_per_100.salt_g],
  m: [
    f.nutrients_per_100.micros?.vitamin_a_ug ?? 0, f.nutrients_per_100.micros?.betacarotene_ug ?? 0,
    f.nutrients_per_100.micros?.vitamin_b1_mg ?? 0, f.nutrients_per_100.micros?.vitamin_b2_mg ?? 0,
    f.nutrients_per_100.micros?.vitamin_b6_mg ?? 0, f.nutrients_per_100.micros?.vitamin_b12_ug ?? 0,
    f.nutrients_per_100.micros?.niacin_mg ?? 0, f.nutrients_per_100.micros?.folate_ug ?? 0,
    f.nutrients_per_100.micros?.pantothenic_acid_mg ?? 0, f.nutrients_per_100.micros?.vitamin_c_mg ?? 0,
    f.nutrients_per_100.micros?.vitamin_d_ug ?? 0, f.nutrients_per_100.micros?.vitamin_e_mg ?? 0,
    f.nutrients_per_100.micros?.sodium_mg ?? 0, f.nutrients_per_100.micros?.potassium_mg ?? 0,
    f.nutrients_per_100.micros?.chloride_mg ?? 0, f.nutrients_per_100.micros?.calcium_mg ?? 0,
    f.nutrients_per_100.micros?.magnesium_mg ?? 0, f.nutrients_per_100.micros?.phosphorus_mg ?? 0,
    f.nutrients_per_100.micros?.iron_mg ?? 0, f.nutrients_per_100.micros?.iodide_ug ?? 0,
    f.nutrients_per_100.micros?.zinc_mg ?? 0,
  ],
}));
fs.writeFileSync(process.argv[2], JSON.stringify({ count: rows.length, rows }));
console.log(`wrote ${rows.length} foods`);
