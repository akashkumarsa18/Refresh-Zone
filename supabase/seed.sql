-- Sample menu, raw materials, recipes and opening stock for development.
-- Run as the database owner (Supabase SQL editor or `supabase db reset`).
-- Prices and costs are placeholders: replace them with Refresh Zone's real numbers.

insert into public.raw_materials (name, stock_unit, reorder_level, cost_per_unit) values
  ('Curd',              'l',   3,    60),
  ('Milk',              'l',   3,    56),
  ('Sugar',             'kg',  2,    45),
  ('Mango Pulp',        'l',   1,   150),
  ('Rose Syrup',        'l',   0.5, 220),
  ('Chia Seeds',        'kg',  0.5, 400),
  ('Lemon',             'pcs', 20,    4),
  ('Mint Leaves',       'g',   100,  0.2),
  ('Soda',              'l',   2,    40),
  ('Blue Curacao Syrup','l',   0.5, 300),
  ('Orange',            'pcs', 20,    8),
  ('Watermelon',        'kg',  5,    25),
  ('Ice',               'kg',  5,    10),
  ('Cup 350ml',         'pcs', 100,   2),
  ('Straw',             'pcs', 100, 0.5)
on conflict (name) do nothing;

with menu (category, name, price, sort_order) as (
  values
    ('Lassi',            'Sweet Lassi',        50, 1),
    ('Lassi',            'Mango Lassi',        70, 2),
    ('Lassi',            'Rose Lassi',         60, 3),
    ('Mocktails',        'Virgin Mojito',      80, 1),
    ('Mocktails',        'Blue Lagoon',        90, 2),
    ('Chia Seed Drinks', 'Lemon Chia Cooler',  60, 1),
    ('Chia Seed Drinks', 'Mango Chia',         80, 2),
    ('Fruit Juices',     'Orange Juice',       70, 1),
    ('Fruit Juices',     'Watermelon Juice',   60, 2)
)
insert into public.products (category_id, name, price, sort_order)
select c.id, m.name, m.price, m.sort_order
  from menu m join public.categories c on c.name = m.category
on conflict (category_id, name) do nothing;

with recipe (product, material, quantity, unit) as (
  values
    ('Sweet Lassi',       'Curd',               250, 'ml'),
    ('Sweet Lassi',       'Sugar',               30, 'g'),
    ('Sweet Lassi',       'Cup 350ml',            1, 'pcs'),
    ('Mango Lassi',       'Curd',               200, 'ml'),
    ('Mango Lassi',       'Mango Pulp',          50, 'ml'),
    ('Mango Lassi',       'Sugar',               20, 'g'),
    ('Mango Lassi',       'Cup 350ml',            1, 'pcs'),
    ('Rose Lassi',        'Curd',               220, 'ml'),
    ('Rose Lassi',        'Rose Syrup',          30, 'ml'),
    ('Rose Lassi',        'Cup 350ml',            1, 'pcs'),
    ('Virgin Mojito',     'Lemon',                1, 'pcs'),
    ('Virgin Mojito',     'Mint Leaves',          5, 'g'),
    ('Virgin Mojito',     'Sugar',               25, 'g'),
    ('Virgin Mojito',     'Soda',               200, 'ml'),
    ('Virgin Mojito',     'Ice',                100, 'g'),
    ('Virgin Mojito',     'Cup 350ml',            1, 'pcs'),
    ('Virgin Mojito',     'Straw',                1, 'pcs'),
    ('Blue Lagoon',       'Blue Curacao Syrup',  30, 'ml'),
    ('Blue Lagoon',       'Lemon',                1, 'pcs'),
    ('Blue Lagoon',       'Soda',               200, 'ml'),
    ('Blue Lagoon',       'Ice',                100, 'g'),
    ('Blue Lagoon',       'Cup 350ml',            1, 'pcs'),
    ('Blue Lagoon',       'Straw',                1, 'pcs'),
    ('Lemon Chia Cooler', 'Chia Seeds',          10, 'g'),
    ('Lemon Chia Cooler', 'Lemon',                1, 'pcs'),
    ('Lemon Chia Cooler', 'Sugar',               25, 'g'),
    ('Lemon Chia Cooler', 'Ice',                100, 'g'),
    ('Lemon Chia Cooler', 'Cup 350ml',            1, 'pcs'),
    ('Mango Chia',        'Chia Seeds',          10, 'g'),
    ('Mango Chia',        'Mango Pulp',          80, 'ml'),
    ('Mango Chia',        'Milk',               150, 'ml'),
    ('Mango Chia',        'Cup 350ml',            1, 'pcs'),
    ('Orange Juice',      'Orange',               3, 'pcs'),
    ('Orange Juice',      'Ice',                 50, 'g'),
    ('Orange Juice',      'Cup 350ml',            1, 'pcs'),
    ('Watermelon Juice',  'Watermelon',         400, 'g'),
    ('Watermelon Juice',  'Ice',                 50, 'g'),
    ('Watermelon Juice',  'Cup 350ml',            1, 'pcs')
)
insert into public.recipe_items (product_id, raw_material_id, quantity, unit)
select p.id, rm.id, r.quantity, r.unit
  from recipe r
  join public.products p       on p.name = r.product
  join public.raw_materials rm on rm.name = r.material
on conflict (product_id, raw_material_id) do nothing;

-- Opening stock goes through the ledger like every other stock change.
with opening (material, quantity) as (
  values
    ('Curd', 20), ('Milk', 10), ('Sugar', 10), ('Mango Pulp', 5), ('Rose Syrup', 2),
    ('Chia Seeds', 2), ('Lemon', 100), ('Mint Leaves', 500), ('Soda', 10),
    ('Blue Curacao Syrup', 2), ('Orange', 60), ('Watermelon', 20), ('Ice', 20),
    ('Cup 350ml', 500), ('Straw', 500)
)
insert into public.inventory_movements (raw_material_id, movement_type, quantity_delta, unit_cost)
select rm.id, 'adjustment', o.quantity, rm.cost_per_unit
  from opening o
  join public.raw_materials rm on rm.name = o.material
 where not exists (select 1 from public.inventory_movements im where im.raw_material_id = rm.id);
