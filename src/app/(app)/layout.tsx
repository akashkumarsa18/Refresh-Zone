import { Suspense } from "react";
import { LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { getCurrentUser } from "@/lib/auth";
import { signOut } from "@/app/login/actions";
import { BottomNav } from "./bottom-nav";

// Phone-first shell: sticky header, scrolling content, fixed bottom nav.
export default function AppLayout({ children }: LayoutProps<"/">) {
  return (
    <div className="mx-auto flex min-h-dvh w-full max-w-md flex-col bg-background">
      <header className="sticky top-0 z-30 flex h-14 items-center justify-between border-b bg-background/95 px-4 backdrop-blur">
        <span className="font-bold tracking-tight text-primary">Refresh Zone</span>
        <Suspense fallback={<Skeleton className="h-5 w-24" />}>
          <UserMenu />
        </Suspense>
      </header>
      <main className="flex flex-1 flex-col pb-[calc(4rem+env(safe-area-inset-bottom))]">
        {children}
      </main>
      <BottomNav />
    </div>
  );
}

async function UserMenu() {
  const user = await getCurrentUser();

  return (
    <div className="flex items-center gap-1">
      <span className="text-sm text-muted-foreground">
        {user.fullName}
        {user.role === "admin" && " · Admin"}
      </span>
      <form action={signOut}>
        <Button type="submit" variant="ghost" size="icon-sm" aria-label="Sign out">
          <LogOut />
        </Button>
      </form>
    </div>
  );
}
