import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import Link from "next/link";

export default async function DashboardPage() {
  try {
    await requireRole("VIEW_DASHBOARD");
  } catch (err) {
    return (
      <main className="p-4 max-w-2xl mx-auto">
        <h1 className="text-xl font-semibold mb-4">Dashboard</h1>
        <p className="text-sm text-red-600" role="alert">
          {err instanceof PermissionError ? err.message : "Onbekende fout"}
        </p>
      </main>
    );
  }

  const supabase = createSupabaseServerClient();

  const startOfMonth = new Date();
  startOfMonth.setDate(1);
  startOfMonth.setHours(0, 0, 0, 0);

  const [
    { count: openCount },
    { count: closedCount },
    { data: monthInvoices },
    { data: allInvoicesWithCompany },
    { data: outstandingInvoices },
    { data: recentActivity },
  ] = await Promise.all([
    supabase.from("open_tabs").select("id", { count: "exact", head: true }).eq("status", "open"),
    supabase.from("open_tabs").select("id", { count: "exact", head: true }).eq("status", "closed"),
    supabase
      .from("invoices")
      .select("total")
      .gte("issued_at", startOfMonth.toISOString().slice(0, 10)),
    supabase.from("invoices").select("total, companies(name)"),
    supabase
      .from("invoices")
      .select("total, payments(amount)")
      .in("status", ["sent", "overdue"]),
    supabase
      .from("activity_log")
      .select("action, created_at, users(full_name)")
      .order("created_at", { ascending: false })
      .limit(8),
  ]);

  const monthRevenue = (monthInvoices ?? []).reduce((sum, i) => sum + Number(i.total), 0);

  const outstandingAmount = (outstandingInvoices ?? []).reduce((sum: number, inv: any) => {
    const paid = (inv.payments ?? []).reduce((s: number, p: any) => s + Number(p.amount), 0);
    return sum + Math.max(0, Number(inv.total) - paid);
  }, 0);

  const byCompany = new Map<string, number>();
  (allInvoicesWithCompany ?? []).forEach((inv: any) => {
    const name = inv.companies?.name ?? "Onbekend bedrijf";
    byCompany.set(name, (byCompany.get(name) ?? 0) + Number(inv.total));
  });
  const topCompanies = Array.from(byCompany.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5);

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <h1 className="text-xl font-semibold mb-4">Dashboard</h1>

      <div className="grid grid-cols-2 gap-3 mb-6">
        <StatCard label="Open rekeningen" value={String(openCount ?? 0)} href="/open-tabs?status=open" />
        <StatCard
          label="Nog te factureren"
          value={String(closedCount ?? 0)}
          href="/open-tabs?status=closed"
        />
        <StatCard label="Omzet deze maand" value={`€${monthRevenue.toFixed(2)}`} href="/invoices" />
        <StatCard label="Openstaand (nog te betalen)" value={`€${outstandingAmount.toFixed(2)}`} href="/invoices" />
        <StatCard label="Totaal facturen" value={String(allInvoicesWithCompany?.length ?? 0)} href="/invoices" />
      </div>

      <section className="mb-6">
        <h2 className="text-sm font-semibold text-neutral-700 mb-2">Top bedrijven</h2>
        {topCompanies.length === 0 ? (
          <p className="text-sm text-neutral-400">Nog geen facturen.</p>
        ) : (
          <ul className="space-y-1">
            {topCompanies.map(([name, total]) => (
              <li
                key={name}
                className="flex justify-between px-3 py-2 rounded-lg bg-neutral-50 text-sm"
              >
                <span>{name}</span>
                <span className="font-medium">€{total.toFixed(2)}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section>
        <h2 className="text-sm font-semibold text-neutral-700 mb-2">Recente activiteit</h2>
        {!recentActivity?.length ? (
          <p className="text-sm text-neutral-400">Nog geen activiteit.</p>
        ) : (
          <ul className="space-y-1">
            {recentActivity.map((a: any, i) => (
              <li key={i} className="px-3 py-2 rounded-lg bg-neutral-50 text-xs text-neutral-600">
                <span className="text-neutral-400">
                  {new Date(a.created_at).toLocaleString("nl-NL")}
                </span>{" "}
                — <strong>{a.users?.full_name ?? "Onbekende gebruiker"}</strong> {a.action}
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}

function StatCard({ label, value, href }: { label: string; value: string; href: string }) {
  return (
    <Link
      href={href}
      className="min-h-touch px-4 py-3 rounded-lg border border-neutral-200 bg-white block"
    >
      <div className="text-xs text-neutral-500">{label}</div>
      <div className="text-xl font-semibold mt-1">{value}</div>
    </Link>
  );
}
