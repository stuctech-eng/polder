import { LogoutButton } from "@/components/ui/logout-button";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { hasPermission } from "@/lib/user-management/permission-service";
import type { UserRole } from "@/lib/user-management/role-helpers";
import Link from "next/link";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  let role: UserRole | null = null;
  if (user) {
    const { data: profile } = await supabase
      .from("users")
      .select("role")
      .eq("id", user.id)
      .single();
    role = (profile?.role as UserRole) ?? null;
  }

  const can = (permission: Parameters<typeof hasPermission>[1]) =>
    role ? hasPermission(role, permission) : false;

  return (
    <div>
      <header className="flex items-center justify-between px-4 py-3 border-b border-neutral-200 bg-white sticky top-0 z-10">
        <div className="flex items-center gap-4">
          <span className="font-semibold">Polder</span>
          <nav className="flex gap-3 text-sm text-neutral-500">
            {can("VIEW_DASHBOARD") && (
              <Link href="/dashboard" className="min-h-touch flex items-center">
                Dashboard
              </Link>
            )}
            {can("MANAGE_COMPANIES") && (
              <Link href="/companies" className="min-h-touch flex items-center">
                Bedrijven
              </Link>
            )}
            {can("MANAGE_OPEN_TABS") && (
              <Link href="/open-tabs" className="min-h-touch flex items-center">
                Rekeningen
              </Link>
            )}
            {can("MANAGE_INVOICES") && (
              <Link href="/invoices" className="min-h-touch flex items-center">
                Facturen
              </Link>
            )}
            {can("VIEW_DAILY_CLOSING") && (
              <Link href="/daily-closing" className="min-h-touch flex items-center">
                Dagafsluiting
              </Link>
            )}
            {can("MANAGE_TEAM") && (
              <Link href="/team" className="min-h-touch flex items-center">
                Team
              </Link>
            )}
          </nav>
        </div>
        <LogoutButton />
      </header>
      {children}
    </div>
  );
}
