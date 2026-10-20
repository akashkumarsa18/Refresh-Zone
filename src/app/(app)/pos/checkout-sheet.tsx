"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Banknote, Loader2, Minus, Plus, Smartphone, SplitSquareHorizontal, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { createClient } from "@/lib/supabase/client";
import type { Enums } from "@/lib/database.types";
import { cn, formatINR } from "@/lib/utils";
import { cartTotals, cashSuggestions, type Cart, type CartAction } from "./cart";

type PaymentMethod = Enums<"payment_method">;

const PAYMENT_OPTIONS: { value: PaymentMethod; label: string; icon: typeof Banknote }[] = [
  { value: "cash", label: "Cash", icon: Banknote },
  { value: "upi", label: "UPI", icon: Smartphone },
  { value: "split", label: "Split", icon: SplitSquareHorizontal },
];

export function CheckoutSheet({
  open,
  onOpenChange,
  cart,
  dispatch,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  cart: Cart;
  dispatch: (action: CartAction) => void;
}) {
  const router = useRouter();
  const [method, setMethod] = useState<PaymentMethod>("cash");
  const [received, setReceived] = useState<number | null>(null);
  const [splitCash, setSplitCash] = useState("");
  const [submitting, setSubmitting] = useState(false);
  // One idempotency key per cart: a retry after a dropped connection reuses
  // it, so the server returns the original bill instead of charging twice.
  const pendingTxn = useRef<{ cart: Cart; id: string } | null>(null);

  const { items, total } = cartTotals(cart);
  const lines = [...cart.values()];
  const splitCashAmount = Number(splitCash || 0);
  const splitInvalid =
    method === "split" && (!(splitCashAmount > 0) || splitCashAmount >= total);
  const change = method === "cash" && received !== null ? received - total : null;

  function resetPayment() {
    setMethod("cash");
    setReceived(null);
    setSplitCash("");
  }

  async function charge() {
    if (items === 0 || splitInvalid) return;

    if (pendingTxn.current?.cart !== cart) {
      pendingTxn.current = { cart, id: crypto.randomUUID() };
    }

    setSubmitting(true);
    const supabase = createClient();
    const { data: sale, error } = await supabase.rpc("process_sale", {
      p_client_txn_id: pendingTxn.current.id,
      p_items: lines.map((l) => ({ product_id: l.product.id, quantity: l.quantity })),
      p_payment_method: method,
      p_cash_amount: method === "split" ? splitCashAmount : null,
    });
    setSubmitting(false);

    if (error) {
      if (error.message.includes("No open shift")) {
        toast.error("The shift was closed. Open a new shift to continue.");
        onOpenChange(false);
        router.refresh();
      } else if (error.message.toLowerCase().includes("fetch")) {
        toast.error("No connection. Tap Charge again — it will not bill twice.");
      } else {
        toast.error(error.message);
      }
      return;
    }

    toast.success(`Bill #${sale.bill_no} · ${formatINR(sale.total)}`, {
      description:
        change !== null && change > 0 ? `Give change: ${formatINR(change)}` : paymentLabel(sale),
    });
    pendingTxn.current = null;
    dispatch({ type: "clear" });
    resetPayment();
    onOpenChange(false);
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-h-[90dvh] max-w-md gap-0 rounded-t-2xl">
        <SheetHeader className="border-b">
          <SheetTitle>Current order</SheetTitle>
          <SheetDescription>
            {items} {items === 1 ? "item" : "items"}
          </SheetDescription>
        </SheetHeader>

        <ul className="flex-1 divide-y overflow-y-auto px-4">
          {lines.map(({ product, quantity }) => (
            <li key={product.id} className="flex items-center gap-3 py-3">
              <div className="flex min-w-0 flex-1 flex-col">
                <span className="truncate font-medium">{product.name}</span>
                <span className="text-sm text-muted-foreground">
                  {formatINR(product.price)} × {quantity} = {formatINR(product.price * quantity)}
                </span>
              </div>
              <div className="flex items-center gap-1">
                <Button
                  variant="outline"
                  size="icon-lg"
                  aria-label={`Remove one ${product.name}`}
                  onClick={() =>
                    dispatch({ type: "set", productId: product.id, quantity: quantity - 1 })
                  }
                >
                  {quantity === 1 ? <Trash2 /> : <Minus />}
                </Button>
                <span className="w-8 text-center font-semibold tabular-nums">{quantity}</span>
                <Button
                  variant="outline"
                  size="icon-lg"
                  aria-label={`Add one ${product.name}`}
                  onClick={() =>
                    dispatch({ type: "set", productId: product.id, quantity: quantity + 1 })
                  }
                >
                  <Plus />
                </Button>
              </div>
            </li>
          ))}
        </ul>

        <SheetFooter className="gap-4 border-t">
          <div className="grid grid-cols-3 gap-2" role="radiogroup" aria-label="Payment method">
            {PAYMENT_OPTIONS.map(({ value, label, icon: Icon }) => (
              <button
                key={value}
                type="button"
                role="radio"
                aria-checked={method === value}
                onClick={() => setMethod(value)}
                className={cn(
                  "flex h-14 flex-col items-center justify-center gap-1 rounded-lg border text-sm font-medium transition-colors",
                  method === value && "border-primary bg-primary/10 text-primary",
                )}
              >
                <Icon className="size-5" />
                {label}
              </button>
            ))}
          </div>

          {method === "cash" && total > 0 && (
            <div className="flex flex-col gap-2">
              <span className="text-sm text-muted-foreground">Cash received</span>
              <div className="flex gap-2">
                {cashSuggestions(total).map((amount) => (
                  <Button
                    key={amount}
                    type="button"
                    variant={received === amount ? "default" : "outline"}
                    className="h-10 flex-1"
                    onClick={() => setReceived(received === amount ? null : amount)}
                  >
                    {amount === total ? "Exact" : formatINR(amount)}
                  </Button>
                ))}
              </div>
              {change !== null && change > 0 && (
                <p className="text-sm">
                  Change to return: <span className="font-bold">{formatINR(change)}</span>
                </p>
              )}
            </div>
          )}

          {method === "split" && (
            <div className="flex flex-col gap-2">
              <Label htmlFor="split_cash">Cash part (₹)</Label>
              <Input
                id="split_cash"
                type="number"
                inputMode="decimal"
                min={0}
                step="0.01"
                value={splitCash}
                onChange={(e) => setSplitCash(e.target.value)}
                className="h-11"
                aria-invalid={splitCash !== "" && splitInvalid}
              />
              <p className="text-sm text-muted-foreground">
                UPI part:{" "}
                <span className="font-semibold text-foreground">
                  {splitInvalid ? "—" : formatINR(total - splitCashAmount)}
                </span>
              </p>
            </div>
          )}

          <Button
            size="xl"
            className="h-14 text-lg"
            disabled={submitting || items === 0 || splitInvalid}
            onClick={charge}
          >
            {submitting && <Loader2 className="animate-spin" />}
            Charge {formatINR(total)}
          </Button>
          <Button
            variant="ghost"
            className="text-destructive"
            disabled={submitting}
            onClick={() => {
              dispatch({ type: "clear" });
              resetPayment();
              onOpenChange(false);
            }}
          >
            Clear order
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}

function paymentLabel(sale: { payment_method: PaymentMethod; cash_amount: number; upi_amount: number }) {
  if (sale.payment_method === "split") {
    return `Cash ${formatINR(sale.cash_amount)} + UPI ${formatINR(sale.upi_amount)}`;
  }
  return sale.payment_method === "cash" ? "Paid in cash" : "Paid by UPI";
}
