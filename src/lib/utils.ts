import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const inr = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  maximumFractionDigits: 2,
  minimumFractionDigits: 0,
});

export function formatINR(value: number | string | null | undefined) {
  return inr.format(Number(value ?? 0) || 0); // || 0 turns -0 into 0
}

const time = new Intl.DateTimeFormat("en-IN", {
  timeZone: "Asia/Kolkata",
  hour: "numeric",
  minute: "2-digit",
  day: "numeric",
  month: "short",
});

export function formatDateTime(value: string | Date) {
  return time.format(new Date(value));
}
