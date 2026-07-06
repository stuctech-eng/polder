import { createSupabaseServerClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import CloseTabButton from "./close-button";
import { ReceiptsSection } from "./receipts-section";
import Link from "next/link";

export default async function OpenTabDetailPage({
  params,
}: {
  params: { id: string };
}) {
  const supabase = createSupabaseServerClient();

  const { data: tab, error } = await supabase
    .from("open_tabs")
    .select("*, companies(name), departments(name), cost_centers(name), projects(name)")
    .eq("id", params.id)
    .single();

  if (error || !tab) {
    notFound();
  }

  const { data: receipts } = await supabase
    .from("receipts")
    .select("*, receipt_lines(*)")
    .eq("open_tab_id", params.id)
    .order("created_at", { ascending: false });

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/open-tabs" className="min-h-touch min-w-touch flex items-center justify-center text-neutral-500">
          ←
        </Link>
        <h1 className="text-xl font-semibold">
          {tab.companies?.name ?? "Geen bedrijf gekoppeld"}
        </h1>
      </div>

      <div className="space-y-2 mb-6 text-sm">
        <Row label="Status" value={tab.status} />
        {tab.departments?.name && <Row label="Afdeling" value={tab.departments.name} />}
        {tab.cost_centers?.name && <Row label="Kostenplaats" value={tab.cost_centers.name} />}
        {tab.projects?.name && <Row label="Project" value={tab.projects.name} />}
        {tab.table_number && <Row label="Tafel" value={tab.table_number} />}
        {tab.guest_count && <Row label="Aantal personen" value={String(tab.guest_count)} />}
        <Row label="Geopend" value={new Date(tab.opened_at).toLocaleString("nl-NL")} />
        {tab.closed_at && (
          <Row label="Gesloten" value={new Date(tab.closed_at).toLocaleString("nl-NL")} />
        )}
      </div>

      <ReceiptsSection openTabId={params.id} initialReceipts={receipts ?? []} />

      {tab.status === "open" && (
        <div className="mt-6">
          <CloseTabButton tabId={tab.id} />
        </div>
      )}
    </main>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between px-4 py-2 rounded-lg bg-neutral-50">
      <span className="text-neutral-500">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  );
}
