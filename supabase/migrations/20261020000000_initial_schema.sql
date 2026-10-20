-- =====================================================================
-- Refresh Zone POS + Recipe-Based Inventory : initial schema
-- Target: Supabase (PostgreSQL 15+)
--
-- Design principles
--   * Every stock change is a row in an append-only ledger
--     (inventory_movements). raw_materials.current_stock is a cached
--     balance maintained ONLY by a trigger on that ledger.
--   * Sales, shifts, wastage, stock checks and purchases are written ONLY
--     through SECURITY DEFINER RPC functions, so prices, totals, stock
--     deductions and shift rules are enforced server-side, never trusted
--     from the phone.
--   * Units: each raw material is stored in its own stock unit (L, kg,
--     pcs ...). Recipes may use any unit of the same dimension (ml, g ...);
--     convert_qty() does the conversion and rejects mismatches (ml -> kg).
--   * Business day = Asia/Kolkata calendar date.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------
create type public.user_role      as enum ('admin', 'staff');
create type public.unit_dimension as enum ('mass', 'volume', 'count');
create type public.payment_method as enum ('cash', 'upi', 'split');
create type public.payment_source as enum ('drawer_cash', 'upi', 'owner'); -- who paid an expense/purchase
create type public.shift_status   as enum ('open', 'closed');
create type public.sale_status    as enum ('completed', 'voided');
create type public.movement_type  as enum ('sale', 'sale_void', 'wastage', 'purchase', 'adjustment');
create type public.wastage_reason as enum ('spoiled', 'expired', 'broken', 'spilled', 'other');

-- ---------------------------------------------------------------------
-- Generic helpers
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Units & conversion
-- ---------------------------------------------------------------------
create table public.units (
  code           text primary key,
  name           text not null,
  dimension      public.unit_dimension not null,
  to_base_factor numeric(18,9) not null check (to_base_factor > 0) -- base: g, ml, pcs
);

insert into public.units (code, name, dimension, to_base_factor) values
  ('g',     'Gram',       'mass',   1),
  ('kg',    'Kilogram',   'mass',   1000),
  ('ml',    'Millilitre', 'volume', 1),
  ('l',     'Litre',      'volume', 1000),
  ('pcs',   'Piece',      'count',  1),
  ('dozen', 'Dozen',      'count',  12);

create or replace function public.convert_qty(p_qty numeric, p_from text, p_to text)
returns numeric
language plpgsql stable
set search_path = public
as $$
declare
  f public.units;
  t public.units;
begin
  if p_from = p_to then
    return p_qty;
  end if;

  select * into f from public.units where code = p_from;
  if not found then raise exception 'Unknown unit: %', p_from; end if;

  select * into t from public.units where code = p_to;
  if not found then raise exception 'Unknown unit: %', p_to; end if;

  if f.dimension <> t.dimension then
    raise exception 'Cannot convert % (%) to % (%)', p_from, f.dimension, p_to, t.dimension;
  end if;

  return p_qty * f.to_base_factor / t.to_base_factor;
end $$;

-- ---------------------------------------------------------------------
-- Users / roles
-- ---------------------------------------------------------------------
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  full_name  text not null,
  role       public.user_role not null default 'staff',
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- New auth users always start as staff; an admin promotes them.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.email, 'Staff'));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_active_user()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and is_active);
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and is_active and role = 'admin');
$$;

-- ---------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------
create table public.categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  sort_order int  not null default 0,
  is_active  boolean not null default true
);

insert into public.categories (name, sort_order) values
  ('Lassi', 1), ('Mocktails', 2), ('Chia Seed Drinks', 3), ('Fruit Juices', 4);

create table public.products (
  id          uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories (id),
  name        text not null,
  price       numeric(10,2) not null check (price >= 0),
  image_url   text,
  sort_order  int not null default 0,
  is_active   boolean not null default true,  -- deactivate, never delete (sales history)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (category_id, name)
);

create trigger products_updated_at before update on public.products
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Raw materials
-- ---------------------------------------------------------------------
create table public.raw_materials (
  id            uuid primary key default gen_random_uuid(),
  name          text not null unique,
  stock_unit    text not null references public.units (code),
  current_stock numeric(16,6) not null default 0,  -- in stock_unit; ledger-maintained, may go negative
  reorder_level numeric(16,6) not null default 0 check (reorder_level >= 0),
  cost_per_unit numeric(12,4) not null default 0 check (cost_per_unit >= 0), -- INR per stock_unit (weighted avg)
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger raw_materials_updated_at before update on public.raw_materials
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Recipes (Bill of Materials): 1 unit of product consumes these
-- ---------------------------------------------------------------------
create table public.recipe_items (
  id              uuid primary key default gen_random_uuid(),
  product_id      uuid not null references public.products (id) on delete cascade,
  raw_material_id uuid not null references public.raw_materials (id) on delete restrict,
  quantity        numeric(12,4) not null check (quantity > 0),
  unit            text not null references public.units (code), -- e.g. 'ml' even if material is stocked in 'l'
  unique (product_id, raw_material_id)
);

create index recipe_items_product_idx on public.recipe_items (product_id);

create or replace function public.validate_recipe_unit()
returns trigger language plpgsql
set search_path = public
as $$
declare
  v_stock_unit text;
begin
  select stock_unit into v_stock_unit from public.raw_materials where id = new.raw_material_id;
  perform public.convert_qty(1, new.unit, v_stock_unit); -- raises on dimension mismatch
  return new;
end $$;

create trigger recipe_items_validate_unit before insert or update on public.recipe_items
  for each row execute function public.validate_recipe_unit();

-- ---------------------------------------------------------------------
-- Shifts
-- ---------------------------------------------------------------------
create table public.shifts (
  id                uuid primary key default gen_random_uuid(),
  status            public.shift_status not null default 'open',
  opened_by         uuid not null references public.profiles (id),
  opened_at         timestamptz not null default now(),
  opening_cash      numeric(10,2) not null check (opening_cash >= 0),
  closed_by         uuid references public.profiles (id),
  closed_at         timestamptz,
  -- reconciliation snapshot, filled by close_shift()
  total_sales       numeric(10,2),
  cash_sales        numeric(10,2),
  upi_sales         numeric(10,2),
  drawer_payouts    numeric(10,2),  -- expenses + purchases paid from the cash drawer
  expected_cash     numeric(10,2),  -- opening_cash + cash_sales - drawer_payouts
  counted_cash      numeric(10,2) check (counted_cash >= 0),
  cash_variance     numeric(10,2) generated always as (counted_cash - expected_cash) stored,
  notes             text,
  constraint shifts_close_consistency check (
    (status = 'open'   and closed_at is null     and counted_cash is null) or
    (status = 'closed' and closed_at is not null and counted_cash is not null)
  )
);

-- Only one open shift (one cash drawer) store-wide.
create unique index shifts_single_open_idx on public.shifts ((true)) where status = 'open';

-- ---------------------------------------------------------------------
-- Sales
-- ---------------------------------------------------------------------
create table public.sales (
  id             uuid primary key default gen_random_uuid(),
  bill_no        bigint generated always as identity unique,
  client_txn_id  uuid not null unique,  -- generated on the phone; makes retries idempotent
  shift_id       uuid not null references public.shifts (id),
  cashier_id     uuid not null references public.profiles (id),
  payment_method public.payment_method not null,
  subtotal       numeric(10,2) not null default 0 check (subtotal >= 0),
  discount       numeric(10,2) not null default 0 check (discount >= 0),
  total          numeric(10,2) not null default 0 check (total >= 0),
  cash_amount    numeric(10,2) not null default 0 check (cash_amount >= 0),
  upi_amount     numeric(10,2) not null default 0 check (upi_amount >= 0),
  total_cost     numeric(12,4) not null default 0,  -- COGS snapshot at time of sale
  status         public.sale_status not null default 'completed',
  voided_by      uuid references public.profiles (id),
  voided_at      timestamptz,
  void_reason    text,
  created_at     timestamptz not null default now(),
  constraint sales_amounts_balance check (cash_amount + upi_amount = total),
  constraint sales_discount_le_subtotal check (discount <= subtotal),
  constraint sales_total_math check (total = subtotal - discount)
);

create index sales_shift_idx      on public.sales (shift_id);
create index sales_created_at_idx on public.sales (created_at);

create table public.sale_items (
  id           uuid primary key default gen_random_uuid(),
  sale_id      uuid not null references public.sales (id) on delete cascade,
  product_id   uuid not null references public.products (id),
  product_name text not null,                    -- snapshot
  unit_price   numeric(10,2) not null check (unit_price >= 0), -- snapshot
  quantity     int not null check (quantity > 0),
  line_total   numeric(10,2) generated always as (unit_price * quantity) stored,
  unit_cost    numeric(12,4) not null default 0  -- recipe cost snapshot
);

create index sale_items_sale_idx    on public.sale_items (sale_id);
create index sale_items_product_idx on public.sale_items (product_id);

-- ---------------------------------------------------------------------
-- Wastage, stock checks, purchases (sources of inventory movements)
-- ---------------------------------------------------------------------
create table public.wastage_logs (
  id              uuid primary key default gen_random_uuid(),
  raw_material_id uuid not null references public.raw_materials (id),
  quantity        numeric(12,4) not null check (quantity > 0),
  unit            text not null references public.units (code),
  reason          public.wastage_reason not null,
  note            text,
  cost_value      numeric(12,2) not null default 0,  -- snapshot of loss in INR
  shift_id        uuid references public.shifts (id),
  logged_by       uuid not null references public.profiles (id),
  created_at      timestamptz not null default now()
);

create table public.stock_adjustments (
  id              uuid primary key default gen_random_uuid(),
  raw_material_id uuid not null references public.raw_materials (id),
  system_qty      numeric(16,6) not null,  -- in stock_unit, before the count
  counted_qty     numeric(16,6) not null check (counted_qty >= 0),
  difference      numeric(16,6) generated always as (counted_qty - system_qty) stored,
  reason          text,
  adjusted_by     uuid not null references public.profiles (id),
  created_at      timestamptz not null default now()
);

create table public.stock_purchases (
  id              uuid primary key default gen_random_uuid(),
  raw_material_id uuid not null references public.raw_materials (id),
  quantity        numeric(12,4) not null check (quantity > 0),
  unit            text not null references public.units (code),
  total_cost      numeric(10,2) not null check (total_cost >= 0),
  paid_via        public.payment_source not null default 'owner',
  supplier        text,
  shift_id        uuid references public.shifts (id),
  created_by      uuid not null references public.profiles (id),
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Inventory ledger (append-only)
-- ---------------------------------------------------------------------
create table public.inventory_movements (
  id              bigint generated always as identity primary key,
  raw_material_id uuid not null references public.raw_materials (id),
  movement_type   public.movement_type not null,
  quantity_delta  numeric(16,6) not null check (quantity_delta <> 0), -- in stock_unit; negative = out
  unit_cost       numeric(12,4),
  sale_id         uuid references public.sales (id),
  wastage_id      uuid references public.wastage_logs (id),
  adjustment_id   uuid references public.stock_adjustments (id),
  purchase_id     uuid references public.stock_purchases (id),
  shift_id        uuid references public.shifts (id),
  created_by      uuid references public.profiles (id),
  created_at      timestamptz not null default now()
);

create index inventory_movements_material_idx on public.inventory_movements (raw_material_id, created_at);
create index inventory_movements_sale_idx     on public.inventory_movements (sale_id) where sale_id is not null;

create or replace function public.apply_inventory_movement()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  update public.raw_materials
     set current_stock = current_stock + new.quantity_delta
   where id = new.raw_material_id;
  return new;
end $$;

create trigger inventory_movements_apply after insert on public.inventory_movements
  for each row execute function public.apply_inventory_movement();

-- ---------------------------------------------------------------------
-- Expenses
-- ---------------------------------------------------------------------
create table public.expense_categories (
  id        uuid primary key default gen_random_uuid(),
  name      text not null unique,
  is_active boolean not null default true
);

insert into public.expense_categories (name) values
  ('Ice'), ('Daily Wages'), ('Electricity'), ('Rent'), ('Transport'), ('Maintenance'), ('Miscellaneous');

create table public.expenses (
  id           uuid primary key default gen_random_uuid(),
  category_id  uuid not null references public.expense_categories (id),
  amount       numeric(10,2) not null check (amount > 0),
  paid_via     public.payment_source not null default 'drawer_cash',
  description  text,
  expense_date date not null default (now() at time zone 'Asia/Kolkata')::date,
  shift_id     uuid references public.shifts (id),
  logged_by    uuid not null default auth.uid() references public.profiles (id),
  created_at   timestamptz not null default now(),
  constraint expenses_drawer_needs_shift check (paid_via <> 'drawer_cash' or shift_id is not null)
);

create index expenses_date_idx on public.expenses (expense_date);

-- Stamp the logger and attach the open shift automatically.
create or replace function public.set_expense_defaults()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  new.logged_by := coalesce(auth.uid(), new.logged_by);
  if new.shift_id is null then
    select id into new.shift_id from public.shifts where status = 'open';
  end if;
  return new;
end $$;

create trigger expenses_defaults before insert on public.expenses
  for each row execute function public.set_expense_defaults();

-- =====================================================================
-- Views (security_invoker => caller's RLS applies)
-- =====================================================================

-- Current recipe cost of one unit of each product.
create view public.v_product_costs with (security_invoker = true) as
select p.id   as product_id,
       p.name,
       p.price,
       coalesce(sum(public.convert_qty(ri.quantity, ri.unit, rm.stock_unit) * rm.cost_per_unit), 0)::numeric(12,4) as unit_cost,
       count(ri.id) as ingredient_count
  from public.products p
  left join public.recipe_items ri  on ri.product_id = p.id
  left join public.raw_materials rm on rm.id = ri.raw_material_id
 group by p.id;

create view public.v_low_stock with (security_invoker = true) as
select id, name, stock_unit, current_stock, reorder_level
  from public.raw_materials
 where is_active and current_stock <= reorder_level
 order by (current_stock / nullif(reorder_level, 0)) nulls first;

create view public.v_daily_sales with (security_invoker = true) as
select (created_at at time zone 'Asia/Kolkata')::date as business_date,
       count(*)              as bills,
       sum(total)            as revenue,
       sum(cash_amount)      as cash_revenue,
       sum(upi_amount)       as upi_revenue,
       sum(discount)         as discounts,
       sum(total_cost)       as cogs
  from public.sales
 where status = 'completed'
 group by 1;

create view public.v_top_items with (security_invoker = true) as
select (s.created_at at time zone 'Asia/Kolkata')::date as business_date,
       si.product_id,
       si.product_name,
       sum(si.quantity)   as qty_sold,
       sum(si.line_total) as revenue
  from public.sale_items si
  join public.sales s on s.id = si.sale_id
 where s.status = 'completed'
 group by 1, 2, 3;

-- Net profit = revenue - COGS - wastage loss - operating expenses.
-- (Stock purchases are inventory, not expenses; they hit P&L via COGS.)
create view public.v_daily_pnl with (security_invoker = true) as
with days as (
  select business_date from public.v_daily_sales
  union
  select expense_date from public.expenses
  union
  select (created_at at time zone 'Asia/Kolkata')::date from public.wastage_logs
),
exp as (
  select expense_date as business_date, sum(amount) as expenses
    from public.expenses group by 1
),
wst as (
  select (created_at at time zone 'Asia/Kolkata')::date as business_date, sum(cost_value) as wastage
    from public.wastage_logs group by 1
)
select d.business_date,
       coalesce(s.revenue, 0)  as revenue,
       coalesce(s.cogs, 0)     as cogs,
       coalesce(w.wastage, 0)  as wastage,
       coalesce(e.expenses, 0) as expenses,
       coalesce(s.revenue, 0) - coalesce(s.cogs, 0) - coalesce(w.wastage, 0) - coalesce(e.expenses, 0) as net_profit
  from days d
  left join public.v_daily_sales s on s.business_date = d.business_date
  left join exp e on e.business_date = d.business_date
  left join wst w on w.business_date = d.business_date;

-- =====================================================================
-- RPC functions (the only write path for transactional tables)
-- =====================================================================

-- ---------- Shifts ----------
create or replace function public.open_shift(p_opening_cash numeric)
returns public.shifts
language plpgsql security definer
set search_path = public
as $$
declare
  v_shift public.shifts;
begin
  if not public.is_active_user() then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  insert into public.shifts (opened_by, opening_cash)
  values (auth.uid(), p_opening_cash)
  returning * into v_shift;

  return v_shift;
exception
  when unique_violation then
    raise exception 'A shift is already open. Close it before opening a new one.';
end $$;

create or replace function public.close_shift(p_shift_id uuid, p_counted_cash numeric, p_notes text default null)
returns public.shifts
language plpgsql security definer
set search_path = public
as $$
declare
  v_shift    public.shifts;
  v_total    numeric(10,2);
  v_cash     numeric(10,2);
  v_upi      numeric(10,2);
  v_payouts  numeric(10,2);
begin
  if not public.is_active_user() then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  -- Locks the shift; in-flight sales hold FOR SHARE on it, so we wait for them.
  select * into v_shift from public.shifts where id = p_shift_id for update;
  if not found or v_shift.status <> 'open' then
    raise exception 'Shift is not open';
  end if;

  select coalesce(sum(total), 0), coalesce(sum(cash_amount), 0), coalesce(sum(upi_amount), 0)
    into v_total, v_cash, v_upi
    from public.sales
   where shift_id = p_shift_id and status = 'completed';

  select coalesce(sum(amount), 0) into v_payouts
    from (
      select amount     from public.expenses        where shift_id = p_shift_id and paid_via = 'drawer_cash'
      union all
      select total_cost from public.stock_purchases where shift_id = p_shift_id and paid_via = 'drawer_cash'
    ) x;

  update public.shifts
     set status         = 'closed',
         closed_by      = auth.uid(),
         closed_at      = now(),
         total_sales    = v_total,
         cash_sales     = v_cash,
         upi_sales      = v_upi,
         drawer_payouts = v_payouts,
         expected_cash  = opening_cash + v_cash - v_payouts,
         counted_cash   = p_counted_cash,
         notes          = p_notes
   where id = p_shift_id
  returning * into v_shift;

  return v_shift;
end $$;

-- ---------- Sales ----------
-- p_items: [{"product_id": "<uuid>", "quantity": 2}, ...]
-- Prices and costs come from the database, never from the client.
create or replace function public.process_sale(
  p_client_txn_id  uuid,
  p_items          jsonb,
  p_payment_method public.payment_method,
  p_discount       numeric default 0,
  p_cash_amount    numeric default null  -- only for 'split'; UPI gets the remainder
)
returns public.sales
language plpgsql security definer
set search_path = public
as $$
declare
  v_sale     public.sales;
  v_shift_id uuid;
  v_lines    int;
  v_subtotal numeric(10,2);
  v_cost     numeric(12,4);
  v_total    numeric(10,2);
  v_cash     numeric(10,2);
  v_upi      numeric(10,2);
begin
  if not public.is_active_user() then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  -- Idempotent retry (flaky mobile network): return the original bill.
  select * into v_sale from public.sales where client_txn_id = p_client_txn_id;
  if found then
    return v_sale;
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Cart is empty';
  end if;
  if exists (select 1 from jsonb_array_elements(p_items) e
              where coalesce((e ->> 'quantity')::int, 0) <= 0) then
    raise exception 'Every cart line needs a quantity of at least 1';
  end if;

  -- FOR SHARE: concurrent sales proceed, close_shift() waits for them.
  select id into v_shift_id from public.shifts where status = 'open' for share;
  if v_shift_id is null then
    raise exception 'No open shift. Open a shift before making sales.';
  end if;

  insert into public.sales (client_txn_id, shift_id, cashier_id, payment_method)
  values (p_client_txn_id, v_shift_id, auth.uid(), p_payment_method)
  on conflict (client_txn_id) do nothing
  returning * into v_sale;

  if not found then  -- a concurrent retry won the race
    select * into v_sale from public.sales where client_txn_id = p_client_txn_id;
    return v_sale;
  end if;

  insert into public.sale_items (sale_id, product_id, product_name, unit_price, quantity, unit_cost)
  select v_sale.id, p.id, p.name, p.price, c.qty, pc.unit_cost
    from (select (e ->> 'product_id')::uuid as product_id, sum((e ->> 'quantity')::int) as qty
            from jsonb_array_elements(p_items) e
           group by 1) c
    join public.products p on p.id = c.product_id and p.is_active
    join public.v_product_costs pc on pc.product_id = p.id;

  get diagnostics v_lines = row_count;
  if v_lines <> (select count(distinct e ->> 'product_id') from jsonb_array_elements(p_items) e) then
    raise exception 'One or more items are unavailable';
  end if;

  select sum(line_total), sum(unit_cost * quantity)
    into v_subtotal, v_cost
    from public.sale_items where sale_id = v_sale.id;

  p_discount := coalesce(p_discount, 0);
  if p_discount < 0 or p_discount > v_subtotal then
    raise exception 'Invalid discount';
  end if;
  v_total := v_subtotal - p_discount;

  case p_payment_method
    when 'cash' then v_cash := v_total; v_upi := 0;
    when 'upi'  then v_cash := 0;       v_upi := v_total;
    when 'split' then
      v_cash := coalesce(p_cash_amount, 0);
      v_upi  := v_total - v_cash;
      if v_cash < 0 or v_upi < 0 then
        raise exception 'Split amounts do not add up to the bill total';
      end if;
  end case;

  update public.sales
     set subtotal = v_subtotal, discount = p_discount, total = v_total,
         cash_amount = v_cash, upi_amount = v_upi, total_cost = v_cost
   where id = v_sale.id
  returning * into v_sale;

  -- Deduct raw materials (converted to each material's stock unit).
  -- Ordered by material id so concurrent sales lock rows in the same order.
  -- Stock is allowed to go negative: never block a sale on a stale count.
  insert into public.inventory_movements
         (raw_material_id, movement_type, quantity_delta, unit_cost, sale_id, shift_id, created_by)
  select ri.raw_material_id, 'sale',
         -sum(public.convert_qty(ri.quantity, ri.unit, rm.stock_unit) * si.quantity),
         rm.cost_per_unit, v_sale.id, v_shift_id, auth.uid()
    from public.sale_items si
    join public.recipe_items ri  on ri.product_id = si.product_id
    join public.raw_materials rm on rm.id = ri.raw_material_id
   where si.sale_id = v_sale.id
   group by ri.raw_material_id, rm.cost_per_unit
   order by ri.raw_material_id;

  return v_sale;
end $$;

create or replace function public.void_sale(p_sale_id uuid, p_reason text)
returns public.sales
language plpgsql security definer
set search_path = public
as $$
declare
  v_sale public.sales;
begin
  if not public.is_admin() then
    raise exception 'Only admins can void sales' using errcode = '42501';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then raise exception 'Sale not found'; end if;
  if v_sale.status = 'voided' then raise exception 'Sale already voided'; end if;

  update public.sales
     set status = 'voided', voided_by = auth.uid(), voided_at = now(), void_reason = p_reason
   where id = p_sale_id
  returning * into v_sale;

  -- Put the ingredients back.
  insert into public.inventory_movements
         (raw_material_id, movement_type, quantity_delta, unit_cost, sale_id, shift_id, created_by)
  select raw_material_id, 'sale_void', -quantity_delta, unit_cost, sale_id, shift_id, auth.uid()
    from public.inventory_movements
   where sale_id = p_sale_id and movement_type = 'sale'
   order by raw_material_id;

  return v_sale;
end $$;

-- ---------- Wastage (staff + admin) ----------
create or replace function public.log_wastage(
  p_raw_material_id uuid,
  p_quantity        numeric,
  p_unit            text,
  p_reason          public.wastage_reason,
  p_note            text default null
)
returns public.wastage_logs
language plpgsql security definer
set search_path = public
as $$
declare
  v_rm       public.raw_materials;
  v_qty      numeric;
  v_shift_id uuid;
  v_log      public.wastage_logs;
begin
  if not public.is_active_user() then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be positive';
  end if;

  select * into v_rm from public.raw_materials where id = p_raw_material_id;
  if not found then raise exception 'Raw material not found'; end if;

  v_qty := public.convert_qty(p_quantity, p_unit, v_rm.stock_unit);
  select id into v_shift_id from public.shifts where status = 'open';

  insert into public.wastage_logs
         (raw_material_id, quantity, unit, reason, note, cost_value, shift_id, logged_by)
  values (p_raw_material_id, p_quantity, p_unit, p_reason, p_note,
          round(v_qty * v_rm.cost_per_unit, 2), v_shift_id, auth.uid())
  returning * into v_log;

  insert into public.inventory_movements
         (raw_material_id, movement_type, quantity_delta, unit_cost, wastage_id, shift_id, created_by)
  values (p_raw_material_id, 'wastage', -v_qty, v_rm.cost_per_unit, v_log.id, v_shift_id, auth.uid());

  return v_log;
end $$;

-- ---------- Physical stock check override (admin) ----------
-- p_counted_qty is in the material's stock_unit.
create or replace function public.adjust_stock(
  p_raw_material_id uuid,
  p_counted_qty     numeric,
  p_reason          text default null
)
returns public.stock_adjustments
language plpgsql security definer
set search_path = public
as $$
declare
  v_rm  public.raw_materials;
  v_adj public.stock_adjustments;
begin
  if not public.is_admin() then
    raise exception 'Only admins can override stock' using errcode = '42501';
  end if;

  select * into v_rm from public.raw_materials where id = p_raw_material_id for update;
  if not found then raise exception 'Raw material not found'; end if;

  insert into public.stock_adjustments (raw_material_id, system_qty, counted_qty, reason, adjusted_by)
  values (p_raw_material_id, v_rm.current_stock, p_counted_qty, p_reason, auth.uid())
  returning * into v_adj;

  if v_adj.difference <> 0 then
    insert into public.inventory_movements
           (raw_material_id, movement_type, quantity_delta, unit_cost, adjustment_id, created_by)
    values (p_raw_material_id, 'adjustment', v_adj.difference, v_rm.cost_per_unit, v_adj.id, auth.uid());
  end if;

  return v_adj;
end $$;

-- ---------- Restock / purchase (admin) ----------
-- Updates the weighted-average cost, then adds stock.
create or replace function public.record_purchase(
  p_raw_material_id uuid,
  p_quantity        numeric,
  p_unit            text,
  p_total_cost      numeric,
  p_paid_via        public.payment_source default 'owner',
  p_supplier        text default null
)
returns public.stock_purchases
language plpgsql security definer
set search_path = public
as $$
declare
  v_rm       public.raw_materials;
  v_qty      numeric;
  v_on_hand  numeric;
  v_shift_id uuid;
  v_purchase public.stock_purchases;
begin
  if not public.is_admin() then
    raise exception 'Only admins can record purchases' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be positive';
  end if;

  select * into v_rm from public.raw_materials where id = p_raw_material_id for update;
  if not found then raise exception 'Raw material not found'; end if;

  v_qty     := public.convert_qty(p_quantity, p_unit, v_rm.stock_unit);
  v_on_hand := greatest(v_rm.current_stock, 0);
  select id into v_shift_id from public.shifts where status = 'open';

  if p_paid_via = 'drawer_cash' and v_shift_id is null then
    raise exception 'Drawer cash can only be used while a shift is open';
  end if;

  update public.raw_materials
     set cost_per_unit = round((v_on_hand * cost_per_unit + p_total_cost) / (v_on_hand + v_qty), 4)
   where id = p_raw_material_id;

  insert into public.stock_purchases
         (raw_material_id, quantity, unit, total_cost, paid_via, supplier, shift_id, created_by)
  values (p_raw_material_id, p_quantity, p_unit, p_total_cost, p_paid_via, p_supplier, v_shift_id, auth.uid())
  returning * into v_purchase;

  insert into public.inventory_movements
         (raw_material_id, movement_type, quantity_delta, unit_cost, purchase_id, shift_id, created_by)
  values (p_raw_material_id, 'purchase', v_qty, round(p_total_cost / v_qty, 4), v_purchase.id, v_shift_id, auth.uid());

  return v_purchase;
end $$;

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table public.units               enable row level security;
alter table public.profiles            enable row level security;
alter table public.categories          enable row level security;
alter table public.products            enable row level security;
alter table public.raw_materials       enable row level security;
alter table public.recipe_items        enable row level security;
alter table public.shifts              enable row level security;
alter table public.sales               enable row level security;
alter table public.sale_items          enable row level security;
alter table public.wastage_logs        enable row level security;
alter table public.stock_adjustments   enable row level security;
alter table public.stock_purchases     enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.expense_categories  enable row level security;
alter table public.expenses            enable row level security;

-- Reference data: readable by any active user, writable by admin.
create policy units_read on public.units for select to authenticated using (public.is_active_user());

create policy profiles_read  on public.profiles for select to authenticated using (public.is_active_user());
create policy profiles_admin on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy categories_read  on public.categories for select to authenticated using (public.is_active_user());
create policy categories_admin on public.categories for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy products_read  on public.products for select to authenticated using (public.is_active_user());
create policy products_admin on public.products for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy recipe_items_read  on public.recipe_items for select to authenticated using (public.is_active_user());
create policy recipe_items_admin on public.recipe_items for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy raw_materials_read  on public.raw_materials for select to authenticated using (public.is_active_user());
create policy raw_materials_admin on public.raw_materials for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy expense_categories_read  on public.expense_categories for select to authenticated using (public.is_active_user());
create policy expense_categories_admin on public.expense_categories for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- current_stock and stock_unit can never be written directly (ledger only).
revoke insert, update on public.raw_materials from authenticated, anon;
grant insert (name, stock_unit, reorder_level, cost_per_unit, is_active) on public.raw_materials to authenticated;
grant update (name, reorder_level, cost_per_unit, is_active)             on public.raw_materials to authenticated;

-- Transactional tables: read-only via RLS; writes go through RPCs above.
create policy shifts_read on public.shifts for select to authenticated
  using (public.is_admin() or (public.is_active_user() and (status = 'open' or opened_by = auth.uid())));

create policy sales_read on public.sales for select to authenticated
  using (public.is_admin()
         or (public.is_active_user() and shift_id in (select id from public.shifts where status = 'open')));

create policy sale_items_read on public.sale_items for select to authenticated
  using (exists (select 1 from public.sales s where s.id = sale_id)); -- inherits sales RLS

create policy wastage_read on public.wastage_logs for select to authenticated
  using (public.is_admin() or (public.is_active_user() and logged_by = auth.uid()));

create policy stock_adjustments_read   on public.stock_adjustments   for select to authenticated using (public.is_admin());
create policy stock_purchases_read     on public.stock_purchases     for select to authenticated using (public.is_admin());
create policy inventory_movements_read on public.inventory_movements for select to authenticated using (public.is_admin());

-- Expenses: staff log against the open shift; admin manages everything.
create policy expenses_read on public.expenses for select to authenticated
  using (public.is_admin() or (public.is_active_user() and logged_by = auth.uid()));
create policy expenses_staff_insert on public.expenses for insert to authenticated
  with check (public.is_active_user()
              and logged_by = auth.uid()
              and shift_id in (select id from public.shifts where status = 'open'));
create policy expenses_admin on public.expenses for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- =====================================================================
-- Function privileges: no anonymous access
-- =====================================================================
revoke execute on function
  public.open_shift(numeric),
  public.close_shift(uuid, numeric, text),
  public.process_sale(uuid, jsonb, public.payment_method, numeric, numeric),
  public.void_sale(uuid, text),
  public.log_wastage(uuid, numeric, text, public.wastage_reason, text),
  public.adjust_stock(uuid, numeric, text),
  public.record_purchase(uuid, numeric, text, numeric, public.payment_source, text)
from public, anon;

grant execute on function
  public.open_shift(numeric),
  public.close_shift(uuid, numeric, text),
  public.process_sale(uuid, jsonb, public.payment_method, numeric, numeric),
  public.void_sale(uuid, text),
  public.log_wastage(uuid, numeric, text, public.wastage_reason, text),
  public.adjust_stock(uuid, numeric, text),
  public.record_purchase(uuid, numeric, text, numeric, public.payment_source, text)
to authenticated;
