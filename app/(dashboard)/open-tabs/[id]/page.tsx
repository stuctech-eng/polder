import { createSupabaseServerClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import CloseTabButton from "./close-button";
import { ReceiptsSection } from "./receipts-section";
import GenerateInvoiceButton from "./generate-invoice-button";
import DownloadInvoiceButton from "./download-invoice-button";
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

  let invoice = null;
  if (tab.status === "invoiced") {
    const { data } = await supabase
      .from("invoices")
      .select("*")
      .eq("company_id", tab.company_id)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    invoice = data;
  }

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

      {tab.status === "closed" && (
        <div className="mt-6">
          <details className="mb-3 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-3">
            <summary className="px-3 py-2 text-sm font-medium text-neutral-700 cursor-pointer">
              Hoe werkt dit? ℹ️
            </summary>
            <div className="px-3 text-sm text-neutral-600">
              <p>
                Genereert een factuur op basis van alle gekoppelde bonnen, inclusief PDF.
                Dit kan niet ongedaan gemaakt worden in deze versie.
              </p>
            </div>
          </details>
          <GenerateInvoiceButton openTabId={params.id} />
        </div>
      )}

      {tab.status === "invoiced" && invoice && (
        <div className="mt-6 space-y-3">
          <div className="space-y-2 text-sm">
            <Row label="Factuurnummer" value={invoice.invoice_number} />
            <Row label="Totaal" value={`€${Number(invoice.total).toFixed(2)}`} />
            <Row label="Vervaldatum" value={new Date(invoice.due_at).toLocaleDateString("nl-NL")} />
          </div>
          <DownloadInvoiceButton invoiceId={invoice.id} />
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
