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

  const navItems: { href: string; label: string; visible: boolean }[] = [
    { href: "/dashboard", label: "Dashboard", visible: can("VIEW_DASHBOARD") },
    { href: "/companies", label: "Bedrijven", visible: can("MANAGE_COMPANIES") },
    { href: "/open-tabs", label: "Rekeningen", visible: can("MANAGE_OPEN_TABS") },
    { href: "/invoices", label: "Facturen", visible: can("MANAGE_INVOICES") },
    { href: "/daily-closing", label: "Dagafsluiting", visible: can("VIEW_DAILY_CLOSING") },
    { href: "/team", label: "Team", visible: can("MANAGE_TEAM") },
    { href: "/handleiding", label: "? Handleiding", visible: true },
  ];

  return (
    <div>
      <header className="border-b border-neutral-200 bg-white sticky top-0 z-10">
        <div className="flex items-center justify-between px-4 py-3">
          <span className="font-semibold">Polder</span>
          <LogoutButton />
        </div>
        <nav
          className="flex gap-2 px-4 pb-3 overflow-x-auto snap-x snap-mandatory"
          style={{ scrollbarWidth: "none" }}
        >
          {navItems
            .filter((item) => item.visible)
            .map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="min-h-touch px-4 flex items-center justify-center rounded-full border border-neutral-200 bg-neutral-50 text-sm text-neutral-700 whitespace-nowrap snap-start active:bg-neutral-100"
              >
                {item.label}
              </Link>
            ))}
        </nav>
      </header>
      {children}
    </div>
  );
}
