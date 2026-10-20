import { Suspense } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getCurrentUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { formatDateTime, formatINR } from "@/lib/utils";
import { CloseShiftForm } from "./close-shift-form";

export default function ShiftPage() {
  return (
    <div className="flex flex-col gap-4 p-4">
      <h1 className="text-xl font-bold">Shift</h1>
      <Suspense fallback={<Skeleton className="h-80 rounded-xl" />}>
        <ShiftLoader />
      </Suspense>
    </div>
  );
}

async function ShiftLoader() {
  await getCurrentUser();
  const supabase = await createClient();

  const { data: shift, error } = await supabase
    .from("shifts")
    .select("id, opened_by, opened_at, opening_cash")
    .eq("status", "open")
    .maybeSingle();
  if (error) throw new Error(error.message);

  if (!shift) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No shift is open</CardTitle>
          <CardDescription>Open a shift from the Sell screen to start taking orders.</CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild size="xl" className="w-full">
            <Link href="/pos">Go to Sell</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  const [openerRes, salesRes] = await Promise.all([
    supabase.from("profiles").select("full_name").eq("id", shift.opened_by).maybeSingle(),
    supabase.from("sales").select("total").eq("shift_id", shift.id).eq("status", "completed"),
  ]);
  if (salesRes.error) throw new Error(salesRes.error.message);

  const bills = salesRes.data.length;
  const salesTotal = salesRes.data.reduce((sum, s) => sum + Number(s.total), 0);

  return (
    <CloseShiftForm
      shiftId={shift.id}
      summary={
        <Card className="gap-4">
          <CardHeader>
            <CardTitle>Current shift</CardTitle>
            <CardDescription>
              Opened by {openerRes.data?.full_name ?? "—"} at {formatDateTime(shift.opened_at)}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <dl className="grid grid-cols-3 gap-3 text-center">
              <Stat label="Opening cash" value={formatINR(shift.opening_cash)} />
              <Stat label="Bills" value={String(bills)} />
              <Stat label="Sales" value={formatINR(salesTotal)} />
            </dl>
          </CardContent>
        </Card>
      }
    />
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col gap-1 rounded-lg bg-muted p-3">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="text-base font-bold tabular-nums">{value}</dd>
    </div>
  );
}
