"use server";

import { refresh } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/database.types";

export type OpenShiftState = { error?: string };

export async function openShift(_prev: OpenShiftState, formData: FormData): Promise<OpenShiftState> {
  const openingCash = parseAmount(formData.get("opening_cash"));
  if (openingCash === null) {
    return { error: "Enter the cash in the drawer (0 if empty)." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("open_shift", { p_opening_cash: openingCash });
  if (error) return { error: error.message };

  refresh();
  return {};
}

export type CloseShiftState = { error?: string; closed?: Tables<"shifts"> };

export async function closeShift(_prev: CloseShiftState, formData: FormData): Promise<CloseShiftState> {
  const shiftId = String(formData.get("shift_id") ?? "");
  const countedCash = parseAmount(formData.get("counted_cash"));
  const notes = String(formData.get("notes") ?? "").trim() || null;

  if (!shiftId) return { error: "No shift selected." };
  if (countedCash === null) return { error: "Enter the cash you counted in the drawer." };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("close_shift", {
    p_shift_id: shiftId,
    p_counted_cash: countedCash,
    p_notes: notes,
  });
  if (error) return { error: error.message };

  return { closed: data };
}

function parseAmount(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  if (text === "") return null;
  const amount = Number(text);
  return Number.isFinite(amount) && amount >= 0 ? Math.round(amount * 100) / 100 : null;
}
