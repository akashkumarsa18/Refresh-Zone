import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { getCurrentUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { OpenShiftCard } from "../shift/open-shift-card";
import { PosScreen } from "./pos-screen";

export default function PosPage() {
  return (
    <Suspense fallback={<PosSkeleton />}>
      <PosLoader />
    </Suspense>
  );
}

async function PosLoader() {
  await getCurrentUser();
  const supabase = await createClient();

  const [shiftRes, categoriesRes, productsRes] = await Promise.all([
    supabase.from("shifts").select("id").eq("status", "open").maybeSingle(),
    supabase.from("categories").select("id, name").eq("is_active", true).order("sort_order"),
    supabase
      .from("products")
      .select("id, category_id, name, price")
      .eq("is_active", true)
      .order("sort_order")
      .order("name"),
  ]);

  const error = shiftRes.error ?? categoriesRes.error ?? productsRes.error;
  if (error) throw new Error(error.message);

  if (!shiftRes.data) {
    return (
      <div className="p-4">
        <OpenShiftCard />
      </div>
    );
  }

  return <PosScreen categories={categoriesRes.data ?? []} products={productsRes.data ?? []} />;
}

function PosSkeleton() {
  return (
    <div className="flex flex-col gap-4 p-4">
      <div className="flex gap-2">
        {Array.from({ length: 4 }, (_, i) => (
          <Skeleton key={i} className="h-9 w-24 rounded-full" />
        ))}
      </div>
      <div className="grid grid-cols-2 gap-3">
        {Array.from({ length: 8 }, (_, i) => (
          <Skeleton key={i} className="h-24 rounded-xl" />
        ))}
      </div>
    </div>
  );
}
