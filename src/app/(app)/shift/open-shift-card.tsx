"use client";

import { useActionState } from "react";
import { Loader2, Timer } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { openShift, type OpenShiftState } from "./actions";

export function OpenShiftCard() {
  const [state, formAction, pending] = useActionState<OpenShiftState, FormData>(openShift, {});

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Timer className="size-5 text-primary" />
          Open a shift to start selling
        </CardTitle>
        <CardDescription>Count the cash in the drawer before the first sale.</CardDescription>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="flex flex-col gap-4">
          <div className="flex flex-col gap-2">
            <Label htmlFor="opening_cash">Opening cash (₹)</Label>
            <Input
              id="opening_cash"
              name="opening_cash"
              type="number"
              inputMode="decimal"
              min={0}
              step="0.01"
              placeholder="0"
              required
              className="h-12 text-lg"
            />
          </div>
          {state.error && (
            <p role="alert" className="text-sm text-destructive">
              {state.error}
            </p>
          )}
          <Button type="submit" size="xl" disabled={pending}>
            {pending && <Loader2 className="animate-spin" />}
            Open shift
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
