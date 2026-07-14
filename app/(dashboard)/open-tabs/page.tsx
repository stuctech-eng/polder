import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import Link from "next/link";

const STATUS_LABELS: Record<string, string> = {
  open: "Open",
  closed: "Gesloten",
  invoiced: "Gefactureerd",
};

export default async function OpenTabsPage({
  searchParams,
}: {
  searchParams: { status?: string };
}) {
  try {
    await requireRole("MANAGE_OPEN_TABS");
  } catch (err) {
    return (
      <main className="p-4 max-w-2xl mx-auto">
        <h1 className="text-xl font-semibold mb-4">Rekeningen</h1>
        <p className="text-sm text-red-600" role="alert">
          {err instanceof PermissionError ? err.message : "Onbekende fout"}
        </p>
      </main>
    );
  }

  const status = searchParams.status ?? "open";
  const supabase = createSupabaseServerClient();
  const { data: openTabs, error } = await supabase
    .from("open_tabs")
    .select("id, table_number, guest_count, opened_at, closed_at, companies(name)")
    .eq("status", status)
    .order("opened_at", { ascending: false });

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-semibold">Rekeningen</h1>
        <Link
          href="/open-tabs/new"
          className="min-h-touch min-w-touch px-4 flex items-center justify-center rounded-lg bg-neutral-900 text-white text-sm font-medium"
        >
          + Nieuwe rekening
        </Link>
      </div>

      <div className="flex gap-2 mb-4 border-b border-neutral-200">
        {Object.entries(STATUS_LABELS).map(([value, label]) => (
          <Link
            key={value}
            href={`/open-tabs?status=${value}`}
            className={`min-h-touch px-3 flex items-center text-sm border-b-2 -mb-px ${
              status === value
                ? "border-neutral-900 font-medium text-neutral-900"
                : "border-transparent text-neutral-500"
            }`}
          >
            {label}
          </Link>
        ))}
      </div>

      <details className="mb-4 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-3">
        <summary className="px-3 py-2 text-sm font-medium text-neutral-700 cursor-pointer">
          Hoe werkt dit? ℹ️
        </summary>
        <div className="px-3 text-sm text-neutral-600 space-y-2">
          <p>
            <strong>Open</strong>: de rekening loopt nog, er kunnen bonnen bij komen.{" "}
            <strong>Gesloten</strong>: klaar, maar nog niet gefactureerd.{" "}
            <strong>Gefactureerd</strong>: er is een factuur gegenereerd (volgt in de
            Facturatie-module).
          </p>
        </div>
      </details>

      {error && (
        <p className="text-sm text-red-600 mb-4" role="alert">
          Fout bij ophalen: {error.message}
        </p>
      )}

      <ul className="space-y-2">
        {openTabs?.map((tab: any) => (
          <li key={tab.id}>
            <Link
              href={`/open-tabs/${tab.id}`}
              className="block min-h-touch px-4 py-3 rounded-lg border border-neutral-200 bg-white active:bg-neutral-100"
            >
              <div className="font-medium">
                {tab.companies?.name ?? "Geen bedrijf gekoppeld"}
              </div>
              <div className="text-sm text-neutral-500">
                {tab.table_number && `Tafel ${tab.table_number} · `}
                {tab.guest_count && `${tab.guest_count} personen · `}
                {status === "open"
                  ? `geopend ${new Date(tab.opened_at).toLocaleString("nl-NL")}`
                  : `gesloten ${tab.closed_at ? new Date(tab.closed_at).toLocaleString("nl-NL") : "-"}`}
              </div>
            </Link>
          </li>
        ))}
        {!openTabs?.length && !error && (
          <p className="text-neutral-500 text-sm py-8 text-center">
            Geen {STATUS_LABELS[status].toLowerCase()} rekeningen.
          </p>
        )}
      </ul>
    </main>
  );
}
