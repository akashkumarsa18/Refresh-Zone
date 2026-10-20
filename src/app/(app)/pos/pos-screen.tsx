"use client";

import { useMemo, useReducer, useState } from "react";
import { ChevronUp, ShoppingBag } from "lucide-react";
import { cn, formatINR } from "@/lib/utils";
import { cartReducer, cartTotals, type Cart, type CatalogProduct } from "./cart";
import { CheckoutSheet } from "./checkout-sheet";

type Category = { id: string; name: string };

export function PosScreen({
  categories,
  products,
}: {
  categories: Category[];
  products: CatalogProduct[];
}) {
  const [cart, dispatch] = useReducer(cartReducer, new Map() as Cart);
  const [activeCategory, setActiveCategory] = useState<string | null>(null);
  const [checkoutOpen, setCheckoutOpen] = useState(false);

  const catalog = useMemo(
    () => products.map((p) => ({ ...p, price: Number(p.price) })),
    [products],
  );
  const visible = activeCategory
    ? catalog.filter((p) => p.category_id === activeCategory)
    : catalog;
  const { items, total } = cartTotals(cart);

  function add(product: CatalogProduct) {
    dispatch({ type: "add", product });
    navigator.vibrate?.(10);
  }

  return (
    <div className="flex flex-1 flex-col">
      <div className="sticky top-14 z-20 border-b bg-background/95 backdrop-blur">
        <div className="scrollbar-none flex gap-2 overflow-x-auto px-4 py-3">
          <CategoryChip active={activeCategory === null} onClick={() => setActiveCategory(null)}>
            All
          </CategoryChip>
          {categories.map((c) => (
            <CategoryChip
              key={c.id}
              active={activeCategory === c.id}
              onClick={() => setActiveCategory(c.id)}
            >
              {c.name}
            </CategoryChip>
          ))}
        </div>
      </div>

      {visible.length === 0 ? (
        <p className="p-8 text-center text-sm text-muted-foreground">
          No items here yet. The owner can add drinks from the admin menu.
        </p>
      ) : (
        <div className={cn("grid grid-cols-2 gap-3 p-4", items > 0 && "pb-24")}>
          {visible.map((product) => {
            const qty = cart.get(product.id)?.quantity ?? 0;
            return (
              <button
                key={product.id}
                type="button"
                onClick={() => add(product)}
                className={cn(
                  "relative flex min-h-24 flex-col justify-between rounded-xl border bg-card p-3 text-left shadow-xs transition active:scale-[0.97]",
                  qty > 0 && "border-primary ring-1 ring-primary",
                )}
              >
                <span className="line-clamp-2 pr-6 font-medium leading-snug">{product.name}</span>
                <span className="text-sm font-semibold text-primary">{formatINR(product.price)}</span>
                {qty > 0 && (
                  <span className="absolute top-2 right-2 flex size-6 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
                    {qty}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      )}

      {items > 0 && (
        <div className="fixed inset-x-0 bottom-[calc(4rem+env(safe-area-inset-bottom))] z-20 mx-auto max-w-md px-3 pb-3">
          <button
            type="button"
            onClick={() => setCheckoutOpen(true)}
            className="flex h-14 w-full items-center justify-between rounded-xl bg-primary px-4 text-primary-foreground shadow-lg active:scale-[0.99]"
          >
            <span className="flex items-center gap-2 font-medium">
              <ShoppingBag className="size-5" />
              {items} {items === 1 ? "item" : "items"}
            </span>
            <span className="flex items-center gap-1 text-lg font-bold">
              {formatINR(total)}
              <ChevronUp className="size-5" />
            </span>
          </button>
        </div>
      )}

      <CheckoutSheet
        open={checkoutOpen && items > 0}
        onOpenChange={setCheckoutOpen}
        cart={cart}
        dispatch={dispatch}
      />
    </div>
  );
}

function CategoryChip({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        "h-9 shrink-0 rounded-full border px-4 text-sm font-medium transition-colors",
        active ? "border-primary bg-primary text-primary-foreground" : "bg-card text-foreground",
      )}
    >
      {children}
    </button>
  );
}
