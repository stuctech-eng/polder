import { createSupabaseServerClient } from "@/lib/supabase/server";
import Link from "next/link";

export default async function OpenTabsPage() {
  const supabase = createSupabaseServerClient();
  const { data: openTabs, error } = await supabase
    .from("open_tabs")
    .select("id, table_number, guest_count, opened_at, companies(name)")
    .eq("status", "open")
    .order("opened_at", { ascending: false });

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-semibold">Open rekeningen</h1>
        <Link
          href="/open-tabs/new"
          className="min-h-touch min-w-touch px-4 flex items-center justify-center rounded-lg bg-neutral-900 text-white text-sm font-medium"
        >
          + Nieuwe rekening
        </Link>
      </div>

      <details className="mb-4 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-3">
        <summary className="px-3 py-2 text-sm font-medium text-neutral-700 cursor-pointer">
          Hoe werkt dit? ℹ️
        </summary>
        <div className="px-3 text-sm text-neutral-600 space-y-2">
          <p>
            Open een rekening zodra een zakelijke gast op rekening gaat eten. Koppel het
            bedrijf (en eventueel afdeling/kostenplaats/project). De rekening blijft open
            totdat je 'm sluit — daarna kan die gefactureerd worden.
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
                geopend {new Date(tab.opened_at).toLocaleString("nl-NL")}
              </div>
            </Link>
          </li>
        ))}
        {!openTabs?.length && !error && (
          <p className="text-neutral-500 text-sm py-8 text-center">
            Geen open rekeningen. Open de eerste rekening.
          </p>
        )}
      </ul>
    </main>
  );
}
