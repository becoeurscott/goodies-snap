// Imports recipes from TheMealDB into the catalog_recipes table.
//
// Run locally with the project admin key (never shipped in the app):
//   INSFORGE_URL=https://j7pth4qn.us-east.insforge.app \
//   INSFORGE_API_KEY=<admin key> \
//   MEALDB_KEY=1 \
//   node scripts/import-catalog.mjs
//
// LICENSING: MEALDB_KEY=1 is TheMealDB's development/test key. Their terms require a paid
// supporter key before a PUBLIC App Store release, plus attribution. Seed with "1" while
// building; re-run under the supporter key (same command, new MEALDB_KEY) before launch.
// Idempotent: re-running upserts on (source, source_id), so it never duplicates.

const BASE = process.env.INSFORGE_URL || 'https://j7pth4qn.us-east.insforge.app';
const API_KEY = process.env.INSFORGE_API_KEY;
const MEALDB_KEY = process.env.MEALDB_KEY || '1';
const LIMIT = Number(process.env.LIMIT || '0'); // 0 = no cap

if (!API_KEY) {
  console.error('Set INSFORGE_API_KEY to the project admin key.');
  process.exit(1);
}

const MEALDB = `https://www.themealdb.com/api/json/v1/${MEALDB_KEY}`;

// Maps a loose ingredient name to one of the app's supermarket aisles. Mirrors
// Aisle.guess(for:) in Models.swift so the catalog matches on-device categorization.
const AISLES = [
  ['Seafood', ['salmon', 'tuna', 'shrimp', 'prawn', 'cod', 'fish', 'crab', 'squid', 'octopus', 'anchov', 'haddock', 'mackerel']],
  ['Meat', ['chicken', 'beef', 'pork', 'lamb', 'bacon', 'ham', 'sausage', 'turkey', 'steak', 'mince', 'veal', 'duck', 'chorizo']],
  ['Dairy', ['milk', 'cheese', 'yogurt', 'yoghurt', 'butter', 'cream', 'feta', 'mozzarella', 'parmesan', 'egg']],
  ['Produce', ['tomato', 'onion', 'garlic', 'lettuce', 'spinach', 'cucumber', 'pepper', 'carrot', 'potato',
    'avocado', 'lime', 'lemon', 'herb', 'basil', 'cilantro', 'coriander', 'parsley', 'cabbage', 'ginger',
    'broccoli', 'mushroom', 'corn', 'bean', 'pea', 'apple', 'mango', 'salad', 'greens', 'scallion', 'celery',
    'zucchini', 'aubergine', 'eggplant', 'chilli', 'chili', 'leek', 'shallot', 'lime', 'banana', 'berry']],
  ['Spices', ['salt', 'peppercorn', 'cumin', 'paprika', 'curry', 'spice', 'cinnamon', 'turmeric', 'oregano',
    'thyme', 'rosemary', 'bay leaf', 'nutmeg', 'cardamom', 'clove', 'saffron']],
  ['Pantry', ['rice', 'pasta', 'noodle', 'bread', 'tortilla', 'flour', 'sugar', 'oil', 'vinegar', 'sauce',
    'soy', 'sesame', 'stock', 'broth', 'quinoa', 'couscous', 'lentil', 'chickpea', 'honey', 'wine', 'water',
    'tomato puree', 'passata', 'coconut milk', 'mustard', 'ketchup', 'yeast', 'baking', 'cornflour', 'nut']],
];

function aisleFor(name) {
  const n = name.toLowerCase();
  for (const [aisle, keys] of AISLES) if (keys.some((k) => n.includes(k))) return aisle;
  return 'Other';
}

// TheMealDB gives free-text instructions; split into clean, one-action steps.
function splitSteps(text) {
  if (!text) return [];
  return text
    .replace(/\r/g, '')
    .split(/\n+|(?<=\.)\s+(?=[A-Z0-9])/)
    .map((s) => s.replace(/^\s*(step\s*\d+[:.)]?|\d+[:.)])\s*/i, '').trim())
    .filter((s) => s.length > 3)
    .slice(0, 25);
}

function mealToRecipe(m) {
  const ingredients = [];
  for (let i = 1; i <= 20; i++) {
    const name = (m[`strIngredient${i}`] || '').trim();
    if (!name) continue;
    const qty = (m[`strMeasure${i}`] || '').trim();
    ingredients.push({ name, qty: qty || 'to taste', category: aisleFor(name) });
  }
  const tags = (m.strTags || '').split(',').map((t) => t.trim()).filter(Boolean);
  return {
    source: 'themealdb',
    source_id: m.idMeal,
    title: m.strMeal,
    cuisine: m.strArea || '',
    category: m.strCategory || '',
    image_url: m.strMealThumb || null,
    // TheMealDB has no timing/nutrition; leave honest zeros rather than inventing numbers.
    prep_minutes: 0,
    cook_minutes: 0,
    servings: 4,
    calories_per_serving: 0,
    protein_g: 0, carbs_g: 0, fat_g: 0,
    ingredients,
    steps: splitSteps(m.strInstructions),
    tags,
    notes: m.strYoutube ? `Video: ${m.strYoutube}` : '',
    published: true,
  };
}

async function getJSON(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url} -> ${r.status}`);
  return r.json();
}

async function upsert(recipe) {
  // PostgREST upsert on the unique (source, source_id) index.
  const r = await fetch(`${BASE}/api/database/records/catalog_recipes?on_conflict=source,source_id`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${API_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify([recipe]),
  });
  if (!r.ok) throw new Error(`upsert ${recipe.title}: ${r.status} ${await r.text()}`);
}

async function main() {
  // Enumerate all categories, then all meals per category, then look each up in full.
  const { categories } = await getJSON('https://www.themealdb.com/api/json/v1/1/categories.php');
  const seen = new Set();
  let imported = 0, failed = 0;

  for (const cat of categories) {
    const list = await getJSON(`${MEALDB}/filter.php?c=${encodeURIComponent(cat.strCategory)}`);
    for (const stub of list.meals || []) {
      if (seen.has(stub.idMeal)) continue;
      seen.add(stub.idMeal);
      if (LIMIT && imported >= LIMIT) { console.log(`\nReached LIMIT=${LIMIT}.`); return report(imported, failed); }
      try {
        const full = await getJSON(`${MEALDB}/lookup.php?i=${stub.idMeal}`);
        const meal = full.meals?.[0];
        if (!meal) continue;
        const recipe = mealToRecipe(meal);
        if (!recipe.ingredients.length || !recipe.steps.length) continue; // skip empties
        await upsert(recipe);
        imported++;
        if (imported % 25 === 0) console.log(`  …${imported} imported`);
      } catch (e) {
        failed++;
        console.warn(`  ! ${stub.strMeal}: ${e.message}`);
      }
    }
  }
  report(imported, failed);
}

function report(imported, failed) {
  console.log(`\nDone. Imported/updated ${imported} recipes, ${failed} failures.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
