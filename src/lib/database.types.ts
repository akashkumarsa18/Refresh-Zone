// Hand-written to match supabase/migrations. Once the Supabase project is
// linked, regenerate with `npm run db:types` and delete this comment.

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

type UserRole = "admin" | "staff";
type UnitDimension = "mass" | "volume" | "count";
type PaymentMethod = "cash" | "upi" | "split";
type PaymentSource = "drawer_cash" | "upi" | "owner";
type ShiftStatus = "open" | "closed";
type SaleStatus = "completed" | "voided";
type MovementType = "sale" | "sale_void" | "wastage" | "purchase" | "adjustment";
type WastageReason = "spoiled" | "expired" | "broken" | "spilled" | "other";

type UnitRow = { code: string; name: string; dimension: UnitDimension; to_base_factor: number };

type ProfileRow = {
  id: string;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  created_at: string;
};

type CategoryRow = { id: string; name: string; sort_order: number; is_active: boolean };

type ProductRow = {
  id: string;
  category_id: string;
  name: string;
  price: number;
  image_url: string | null;
  sort_order: number;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

type RawMaterialRow = {
  id: string;
  name: string;
  stock_unit: string;
  current_stock: number;
  reorder_level: number;
  cost_per_unit: number;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

type RecipeItemRow = {
  id: string;
  product_id: string;
  raw_material_id: string;
  quantity: number;
  unit: string;
};

type ShiftRow = {
  id: string;
  status: ShiftStatus;
  opened_by: string;
  opened_at: string;
  opening_cash: number;
  closed_by: string | null;
  closed_at: string | null;
  total_sales: number | null;
  cash_sales: number | null;
  upi_sales: number | null;
  drawer_payouts: number | null;
  expected_cash: number | null;
  counted_cash: number | null;
  cash_variance: number | null;
  notes: string | null;
};

type SaleRow = {
  id: string;
  bill_no: number;
  client_txn_id: string;
  shift_id: string;
  cashier_id: string;
  payment_method: PaymentMethod;
  subtotal: number;
  discount: number;
  total: number;
  cash_amount: number;
  upi_amount: number;
  total_cost: number;
  status: SaleStatus;
  voided_by: string | null;
  voided_at: string | null;
  void_reason: string | null;
  created_at: string;
};

type SaleItemRow = {
  id: string;
  sale_id: string;
  product_id: string;
  product_name: string;
  unit_price: number;
  quantity: number;
  line_total: number;
  unit_cost: number;
};

type WastageLogRow = {
  id: string;
  raw_material_id: string;
  quantity: number;
  unit: string;
  reason: WastageReason;
  note: string | null;
  cost_value: number;
  shift_id: string | null;
  logged_by: string;
  created_at: string;
};

type StockAdjustmentRow = {
  id: string;
  raw_material_id: string;
  system_qty: number;
  counted_qty: number;
  difference: number;
  reason: string | null;
  adjusted_by: string;
  created_at: string;
};

type StockPurchaseRow = {
  id: string;
  raw_material_id: string;
  quantity: number;
  unit: string;
  total_cost: number;
  paid_via: PaymentSource;
  supplier: string | null;
  shift_id: string | null;
  created_by: string;
  created_at: string;
};

type InventoryMovementRow = {
  id: number;
  raw_material_id: string;
  movement_type: MovementType;
  quantity_delta: number;
  unit_cost: number | null;
  sale_id: string | null;
  wastage_id: string | null;
  adjustment_id: string | null;
  purchase_id: string | null;
  shift_id: string | null;
  created_by: string | null;
  created_at: string;
};

type ExpenseCategoryRow = { id: string; name: string; is_active: boolean };

type ExpenseRow = {
  id: string;
  category_id: string;
  amount: number;
  paid_via: PaymentSource;
  description: string | null;
  expense_date: string;
  shift_id: string | null;
  logged_by: string;
  created_at: string;
};

// Write paths for transactional tables go through RPCs, so Insert/Update are
// kept loose here; generated types will tighten them.
type Table<Row> = {
  Row: Row;
  Insert: Partial<Row>;
  Update: Partial<Row>;
  Relationships: [];
};

type View<Row> = { Row: Row; Relationships: [] };

export type Database = {
  public: {
    Tables: {
      units: Table<UnitRow>;
      profiles: Table<ProfileRow>;
      categories: Table<CategoryRow>;
      products: Table<ProductRow>;
      raw_materials: Table<RawMaterialRow>;
      recipe_items: Table<RecipeItemRow>;
      shifts: Table<ShiftRow>;
      sales: Table<SaleRow>;
      sale_items: Table<SaleItemRow>;
      wastage_logs: Table<WastageLogRow>;
      stock_adjustments: Table<StockAdjustmentRow>;
      stock_purchases: Table<StockPurchaseRow>;
      inventory_movements: Table<InventoryMovementRow>;
      expense_categories: Table<ExpenseCategoryRow>;
      expenses: Table<ExpenseRow>;
    };
    Views: {
      v_product_costs: View<{
        product_id: string;
        name: string;
        price: number;
        unit_cost: number;
        ingredient_count: number;
      }>;
      v_low_stock: View<{
        id: string;
        name: string;
        stock_unit: string;
        current_stock: number;
        reorder_level: number;
      }>;
      v_daily_sales: View<{
        business_date: string;
        bills: number;
        revenue: number;
        cash_revenue: number;
        upi_revenue: number;
        discounts: number;
        cogs: number;
      }>;
      v_top_items: View<{
        business_date: string;
        product_id: string;
        product_name: string;
        qty_sold: number;
        revenue: number;
      }>;
      v_daily_pnl: View<{
        business_date: string;
        revenue: number;
        cogs: number;
        wastage: number;
        expenses: number;
        net_profit: number;
      }>;
    };
    Functions: {
      open_shift: { Args: { p_opening_cash: number }; Returns: ShiftRow };
      close_shift: {
        Args: { p_shift_id: string; p_counted_cash: number; p_notes?: string | null };
        Returns: ShiftRow;
      };
      process_sale: {
        Args: {
          p_client_txn_id: string;
          p_items: Json;
          p_payment_method: PaymentMethod;
          p_discount?: number;
          p_cash_amount?: number | null;
        };
        Returns: SaleRow;
      };
      void_sale: { Args: { p_sale_id: string; p_reason: string }; Returns: SaleRow };
      log_wastage: {
        Args: {
          p_raw_material_id: string;
          p_quantity: number;
          p_unit: string;
          p_reason: WastageReason;
          p_note?: string | null;
        };
        Returns: WastageLogRow;
      };
      adjust_stock: {
        Args: { p_raw_material_id: string; p_counted_qty: number; p_reason?: string | null };
        Returns: StockAdjustmentRow;
      };
      record_purchase: {
        Args: {
          p_raw_material_id: string;
          p_quantity: number;
          p_unit: string;
          p_total_cost: number;
          p_paid_via?: PaymentSource;
          p_supplier?: string | null;
        };
        Returns: StockPurchaseRow;
      };
      convert_qty: { Args: { p_qty: number; p_from: string; p_to: string }; Returns: number };
      is_admin: { Args: Record<string, never>; Returns: boolean };
      is_active_user: { Args: Record<string, never>; Returns: boolean };
    };
    Enums: {
      user_role: UserRole;
      unit_dimension: UnitDimension;
      payment_method: PaymentMethod;
      payment_source: PaymentSource;
      shift_status: ShiftStatus;
      sale_status: SaleStatus;
      movement_type: MovementType;
      wastage_reason: WastageReason;
    };
    CompositeTypes: Record<string, never>;
  };
};

type PublicSchema = Database["public"];
export type Tables<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Row"];
export type Views<T extends keyof PublicSchema["Views"]> = PublicSchema["Views"][T]["Row"];
export type Enums<T extends keyof PublicSchema["Enums"]> = PublicSchema["Enums"][T];
