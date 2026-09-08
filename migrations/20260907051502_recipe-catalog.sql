-- Recipe catalog: a browsable, server-side library of curated recipes powering the
-- Discover screen. Read-only to the app; only the importer (admin key) writes here.
--
-- Kept deliberately separate from `posts` (community-authored) and from the device-local
-- starter library: this is editorial content the team controls and can update without an
-- app release.

CREATE TABLE public.catalog_recipes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Where the recipe came from, so attribution and de-duplication are possible.
  source TEXT NOT NULL DEFAULT 'themealdb',
  source_id TEXT,                       -- the provider's own id, for idempotent re-import
  title TEXT NOT NULL,
  cuisine TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',    -- the provider's meal category (Chicken, Dessert…)
  image_url TEXT,
  prep_minutes INT NOT NULL DEFAULT 0,
  cook_minutes INT NOT NULL DEFAULT 0,
  servings INT NOT NULL DEFAULT 2,
  calories_per_serving INT NOT NULL DEFAULT 0,
  protein_g INT NOT NULL DEFAULT 0,
  carbs_g INT NOT NULL DEFAULT 0,
  fat_g INT NOT NULL DEFAULT 0,
  -- [{ name, qty, category }], category is one of the app's supermarket aisles.
  ingredients JSONB NOT NULL DEFAULT '[]'::jsonb,
  steps JSONB NOT NULL DEFAULT '[]'::jsonb,
  tags JSONB NOT NULL DEFAULT '[]'::jsonb,
  notes TEXT NOT NULL DEFAULT '',
  -- Editorial controls for the Discover screen.
  featured BOOLEAN NOT NULL DEFAULT FALSE,
  published BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Idempotent re-import: one row per provider recipe.
CREATE UNIQUE INDEX catalog_recipes_source_uidx
  ON public.catalog_recipes (source, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX catalog_recipes_cuisine_idx ON public.catalog_recipes (cuisine);
CREATE INDEX catalog_recipes_category_idx ON public.catalog_recipes (category);
CREATE INDEX catalog_recipes_featured_idx ON public.catalog_recipes (featured) WHERE featured;

-- Read-only to everyone; writes only via the admin key (RLS is bypassed for that role),
-- so the app can never inject catalog rows.
GRANT SELECT ON public.catalog_recipes TO anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.catalog_recipes FROM anon, authenticated;

ALTER TABLE public.catalog_recipes ENABLE ROW LEVEL SECURITY;

-- Anyone may read published recipes; unpublished ones stay hidden until an editor flips
-- the flag. Browsing Discover does not require an account.
CREATE POLICY "published catalog readable" ON public.catalog_recipes
  FOR SELECT TO anon, authenticated USING (published = TRUE);
