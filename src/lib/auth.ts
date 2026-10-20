import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type CurrentUser = {
  id: string;
  fullName: string;
  role: "admin" | "staff";
};

// Data Access Layer: the single place that turns the session into a user.
// Deduplicated per request with React cache().
export const getCurrentUser = cache(async (): Promise<CurrentUser> => {
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;
  if (!userId) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, full_name, role, is_active")
    .eq("id", userId)
    .maybeSingle();

  if (!profile || !profile.is_active) redirect("/login?error=inactive");

  return { id: profile.id, fullName: profile.full_name, role: profile.role };
});

export async function requireAdmin() {
  const user = await getCurrentUser();
  if (user.role !== "admin") redirect("/pos");
  return user;
}
