"use client";

import { useActionState } from "react";
import Link from "next/link";
import { CheckCircle2, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import type { Tables } from "@/lib/database.types";
import { cn, formatINR } from "@/lib/utils";
import { closeShift, type CloseShiftState } from "./actions";

// Blind count: the cashier enters what is in the drawer before seeing what
// the system expects, then gets the reconciliation.
export function CloseShiftForm({
  shiftId,
  summary,
}: {
  shiftId: string;
  summary: React.ReactNode;
}) {
  const [state, formAction, pending] = useActionState<CloseShiftState, FormData>(closeShift, {});

  if (state.closed) return <Reconciliation shift={state.closed} />;

  return (
    <>
      {summary}
      <Card>
        <CardHeader>
          <CardTitle>Close shift</CardTitle>
          <CardDescription>Count all the cash in the drawer, then enter the total.</CardDescription>
        </CardHeader>
        <CardContent>
          <form action={formAction} className="flex flex-col gap-4">
            <input type="hidden" name="shift_id" value={shiftId} />
            <div className="flex flex-col gap-2">
              <Label htmlFor="counted_cash">Cash counted (₹)</Label>
              <Input
                id="counted_cash"
                name="counted_cash"
                type="number"
                inputMode="decimal"
                min={0}
                step="0.01"
                required
                className="h-12 text-lg"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="notes">Notes (optional)</Label>
              <Textarea id="notes" name="notes" placeholder="Anything the owner should know" />
            </div>
            {state.error && (
              <p role="alert" className="text-sm text-destructive">
                {state.error}
              </p>
            )}
            <Button type="submit" size="xl" variant="destructive" disabled={pending}>
              {pending && <Loader2 className="animate-spin" />}
              Close shift
            </Button>
          </form>
        </CardContent>
      </Card>
    </>
  );
}

function Reconciliation({ shift }: { shift: Tables<"shifts"> }) {
  const variance = Number(shift.cash_variance ?? 0);
  const rows: [string, number | null][] = [
    ["Opening cash", shift.opening_cash],
    ["Cash sales", shift.cash_sales],
    ["Paid out from drawer", shift.drawer_payouts === null ? null : -shift.drawer_payouts],
    ["Expected in drawer", shift.expected_cash],
    ["Counted", shift.counted_cash],
  ];

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <CheckCircle2 className="size-5 text-primary" />
          Shift closed
        </CardTitle>
        <CardDescription>
          Total sales {formatINR(shift.total_sales)} · UPI {formatINR(shift.upi_sales)}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <dl className="flex flex-col divide-y text-sm">
          {rows.map(([label, value]) => (
            <div key={label} className="flex justify-between py-2">
              <dt className="text-muted-foreground">{label}</dt>
              <dd className="font-medium tabular-nums">{formatINR(value)}</dd>
            </div>
          ))}
        </dl>
        <div
          className={cn(
            "flex items-center justify-between rounded-lg p-3 font-semibold",
            variance === 0 && "bg-primary/10 text-primary",
            variance > 0 && "bg-amber-500/10 text-amber-700 dark:text-amber-400",
            variance < 0 && "bg-destructive/10 text-destructive",
          )}
        >
          <span>{variance === 0 ? "Drawer matches" : variance > 0 ? "Extra cash" : "Cash short"}</span>
          <span className="tabular-nums">{formatINR(Math.abs(variance))}</span>
        </div>
        <Button asChild size="xl">
          <Link href="/pos">Done</Link>
        </Button>
      </CardContent>
    </Card>
  );
}
