# Refresh Zone POS

Mobile-first point of sale and recipe-based inventory for Refresh Zone.
Next.js 16 (App Router) · Supabase (Postgres, Auth, RLS) · Tailwind CSS 4 · shadcn/ui.

## What works today

- Email/password sign-in; `admin` and `staff` roles (`profiles.role`)
- Shift gate: no sales until a shift is opened with the drawer's opening cash
- Sell screen: category chips, tap-to-add grid, cart sheet, Cash / UPI / Split,
  quick "cash received" buttons with change due
- Every sale deducts recipe ingredients from stock, converting units (ml → L, g → kg)
- Retrying a sale after a dropped connection never bills twice
- Blind close: the cashier enters the counted cash, then sees expected vs counted

## Setup

1. Create a Supabase project.
2. Run `supabase/migrations/20261020000000_initial_schema.sql` in the SQL editor
   (or `supabase db push`). Optionally run `supabase/seed.sql` for a sample menu.
3. In Authentication → Users, add the owner and each cashier. Then make the owner an admin:
   ```sql
   update public.profiles set role = 'admin' where id = '<owner user id>';
   ```
   Turn off public sign-ups (Authentication → Sign In / Providers) so only accounts you
   create can log in.
4. Copy `.env.example` to `.env.local` and fill in the project URL and publishable key.
5. `npm install && npm run dev`, then open http://localhost:3000 on your phone or in
   the browser's mobile view.

On Vercel, set the same two environment variables in the project settings.

## Scripts

| Command             | What it does                                         |
| ------------------- | ---------------------------------------------------- |
| `npm run dev`       | Dev server                                           |
| `npm run build`     | Production build                                     |
| `npm run lint`      | ESLint                                               |
| `npm run typecheck` | TypeScript                                           |
| `npm run db:types`  | Regenerate `src/lib/database.types.ts` from Supabase |

## Layout

```
supabase/migrations/   schema, RPC functions, RLS, reporting views
supabase/seed.sql      sample menu, recipes and opening stock
src/proxy.ts           refreshes the auth session, sends signed-out users to /login
src/lib/auth.ts        getCurrentUser(): the one place that reads the session
src/app/login/         sign-in
src/app/(app)/pos/     sell screen and checkout
src/app/(app)/shift/   open / close shift
```
