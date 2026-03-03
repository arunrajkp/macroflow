-- ============================================================
--  MacroFlow – Complete Database Schema
--  Project: zfovszmjrtmerasczmsc
--
--  HOW TO RUN:
--  1. Go to: https://supabase.com/dashboard/project/zfovszmjrtmerasczmsc/sql/new
--  2. Select ALL text below (Ctrl+A)
--  3. Paste into the SQL editor
--  4. Click "Run" (or press Ctrl+Enter)
-- ============================================================

-- ── 1. Profiles (extends Supabase auth.users) ────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id                 UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username           TEXT UNIQUE NOT NULL,
  full_name          TEXT,
  avatar_url         TEXT,
  daily_kcal_goal    INTEGER DEFAULT 2000,
  daily_protein_goal INTEGER DEFAULT 150,
  daily_carbs_goal   INTEGER DEFAULT 250,
  daily_fats_goal    INTEGER DEFAULT 65,
  created_at         TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2. Food Library ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.food_items (
  id           BIGSERIAL PRIMARY KEY,
  name         TEXT NOT NULL,
  brand        TEXT,
  serving_size TEXT DEFAULT '100g',
  kcal         NUMERIC(8,2) DEFAULT 0,
  protein_g    NUMERIC(8,2) DEFAULT 0,
  carbs_g      NUMERIC(8,2) DEFAULT 0,
  fats_g       NUMERIC(8,2) DEFAULT 0,
  fiber_g      NUMERIC(8,2) DEFAULT 0,
  is_custom    BOOLEAN DEFAULT FALSE,
  created_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3. Meal Logs ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.meal_logs (
  id           BIGSERIAL PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  meal_type    TEXT NOT NULL CHECK (meal_type IN ('Breakfast','Lunch','Dinner','Snack')),
  meal_name    TEXT,
  portion_size TEXT,
  log_date     DATE NOT NULL DEFAULT CURRENT_DATE,
  notes        TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ── 4. Meal Food Items ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.meal_food_items (
  id           BIGSERIAL PRIMARY KEY,
  meal_log_id  BIGINT NOT NULL REFERENCES public.meal_logs(id) ON DELETE CASCADE,
  food_item_id BIGINT REFERENCES public.food_items(id) ON DELETE SET NULL,
  food_name    TEXT NOT NULL,
  quantity     NUMERIC(8,2) DEFAULT 1,
  kcal         NUMERIC(8,2) DEFAULT 0,
  protein_g    NUMERIC(8,2) DEFAULT 0,
  carbs_g      NUMERIC(8,2) DEFAULT 0,
  fats_g       NUMERIC(8,2) DEFAULT 0
);

-- ── 5. Daily Summary View ─────────────────────────────────────
CREATE OR REPLACE VIEW public.daily_summary AS
SELECT
  ml.user_id,
  ml.log_date,
  ml.meal_type,
  ml.id                          AS meal_log_id,
  ml.meal_name,
  ml.portion_size,
  COALESCE(SUM(mfi.kcal),     0) AS total_kcal,
  COALESCE(SUM(mfi.protein_g),0) AS total_protein,
  COALESCE(SUM(mfi.carbs_g),  0) AS total_carbs,
  COALESCE(SUM(mfi.fats_g),   0) AS total_fats,
  STRING_AGG(mfi.food_name, ', ') AS food_names
FROM public.meal_logs ml
LEFT JOIN public.meal_food_items mfi ON mfi.meal_log_id = ml.id
GROUP BY ml.user_id, ml.log_date, ml.meal_type,
         ml.id, ml.meal_name, ml.portion_size;

-- ── 6. Indexes ───────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_meal_logs_user_date ON public.meal_logs(user_id, log_date);
CREATE INDEX IF NOT EXISTS idx_meal_logs_date      ON public.meal_logs(log_date);
CREATE INDEX IF NOT EXISTS idx_meal_food_log       ON public.meal_food_items(meal_log_id);

-- ── 7. Row Level Security ─────────────────────────────────────
ALTER TABLE public.profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meal_logs       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meal_food_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.food_items      ENABLE ROW LEVEL SECURITY;

-- Profiles: own row only
DROP POLICY IF EXISTS "profiles_select" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update" ON public.profiles;
CREATE POLICY "profiles_select" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "profiles_insert" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Meal logs: own logs only
DROP POLICY IF EXISTS "meal_logs_select" ON public.meal_logs;
DROP POLICY IF EXISTS "meal_logs_insert" ON public.meal_logs;
DROP POLICY IF EXISTS "meal_logs_update" ON public.meal_logs;
DROP POLICY IF EXISTS "meal_logs_delete" ON public.meal_logs;
CREATE POLICY "meal_logs_select" ON public.meal_logs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "meal_logs_insert" ON public.meal_logs FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "meal_logs_update" ON public.meal_logs FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "meal_logs_delete" ON public.meal_logs FOR DELETE USING (auth.uid() = user_id);

-- Meal food items: accessible via parent meal ownership
DROP POLICY IF EXISTS "meal_food_items_select" ON public.meal_food_items;
DROP POLICY IF EXISTS "meal_food_items_insert" ON public.meal_food_items;
DROP POLICY IF EXISTS "meal_food_items_delete" ON public.meal_food_items;
CREATE POLICY "meal_food_items_select" ON public.meal_food_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.meal_logs ml WHERE ml.id = meal_log_id AND ml.user_id = auth.uid()));
CREATE POLICY "meal_food_items_insert" ON public.meal_food_items FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.meal_logs ml WHERE ml.id = meal_log_id AND ml.user_id = auth.uid()));
CREATE POLICY "meal_food_items_delete" ON public.meal_food_items FOR DELETE
  USING (EXISTS (SELECT 1 FROM public.meal_logs ml WHERE ml.id = meal_log_id AND ml.user_id = auth.uid()));

-- Food items: all authenticated users can read; creator can edit custom items
DROP POLICY IF EXISTS "food_items_select" ON public.food_items;
DROP POLICY IF EXISTS "food_items_insert" ON public.food_items;
DROP POLICY IF EXISTS "food_items_update" ON public.food_items;
CREATE POLICY "food_items_select" ON public.food_items FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "food_items_insert" ON public.food_items FOR INSERT WITH CHECK (auth.uid() = created_by OR created_by IS NULL);
CREATE POLICY "food_items_update" ON public.food_items FOR UPDATE USING (auth.uid() = created_by);

-- ── 8. Auto-create Profile on Signup ─────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, username, full_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'full_name', '')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── 9. Seed Food Library (Expanded with Indian Cuisine) ───────
INSERT INTO public.food_items (name, serving_size, kcal, protein_g, carbs_g, fats_g, fiber_g)
VALUES
  ('Soft Boiled Eggs',           '2 eggs',    140, 12,  1,  10, 0),
  ('Greek Yogurt & Honey',       '200g',      185, 18, 20,   4, 0),
  ('Grilled Atlantic Salmon',    '150g',      208, 24,  0,  12, 0),
  ('Avocado Sourdough',          '1 slice',   310,  8, 38,  15, 5),
  ('Chicken Salad',              '1 bowl',    285, 30, 12,  14, 2),
  ('Oatmeal',                    '1 cup',     150,  5, 27,   3, 4),
  ('Protein Shake',              '1 scoop',   180, 30,  8,   3, 0),
  ('Brown Rice & Veggies',       '1 cup',     245,  7, 48,   4, 4),
  ('Scrambled Eggs',             '2 eggs',    200, 14,  2,  15, 0),
  ('Banana',                     '1 medium',   89,  1, 23,   0, 3),
  ('Almonds',                    '30g',        160,  6,  6,  14, 3),
  ('Blueberries',                '100g',        45,  1, 11,   0, 2),
  ('Greek Yogurt',               '150g',       120, 15,  9,   3, 0),
  ('Honey',                      '1 tbsp',      60,  0, 16,   0, 0),
  ('Whole Wheat Bread',          '2 slices',   160,  7, 30,   2, 4),
  ('Turkey Breast',              '100g',        135, 30,  0,   1, 0),
  ('Cottage Cheese',             '100g',         98, 11,  3,   4, 0),
  ('Sweet Potato',               '1 medium',   103,  2, 24,   0, 4),
  ('Broccoli',                   '100g',         34,  3,  7,   0, 3),
  ('Olive Oil',                  '1 tbsp',      119,  0,  0,  14, 0),
  ('Chicken Biryani (Standard)', '1 plate',    650, 30, 90,  18, 4),
  ('Chicken Fried Rice',         '1 bowl',     550, 22, 75,  18, 2),
  ('Chilly Chicken (Dry)',       '1 portion',  320, 28, 12,  16, 1),
  ('Butter Chicken',             '200g',       400, 25,  8,  30, 1),
  ('Paneer Butter Masala',       '200g',       350, 12, 10,  30, 2),
  ('Masala Dosa',                '1 piece',    350,  6, 55,  12, 3),
  ('Idli (2) with Sambar',       '250g',       250,  8, 45,   4, 6),
  ('Dal Tadka',                  '1 bowl',     220, 11, 30,   6, 8),
  ('Chapati / Roti',             '1 piece',    100,  3, 20,   1, 3),
  ('Egg Curry',                  '2 eggs',     280, 15,  8,  20, 1),
  ('Tandoori Chicken',           '1 leg',      220, 25,  2,  12, 0),
  (' केरल Fish Curry',           '200g',       250, 22,  6,  15, 0),
  ('Samosa',                     '1 piece',    250,  4, 25,  15, 2),
  ('Gulab Jamun',                '2 pieces',   320,  4, 50,  12, 0)
ON CONFLICT DO NOTHING;
