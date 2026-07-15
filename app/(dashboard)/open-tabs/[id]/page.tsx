import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getApprovalSettings } from "@/lib/approval/approval-service";
import { requireRole, hasPermission, PermissionError } from "@/lib/user-management/permission-service";
import { notFound } from "next/navigation";
import CloseTabButton from "./close-button";
import { ReceiptsSection } from "./receipts-section";
import GenerateInvoiceButton from "./generate-invoice-button";
import DownloadInvoiceButton from "./download-invoice-button";
import TabEditControls from "./tab-edit-controls";
import Link from "next/link";

export default async function OpenTabDetailPage({
  params,
}: {
  params: { id: string };
}) {
  let ctx;
  try {
    ctx = await requireRole("MANAGE_OPEN_TABS");
  } catch (err) {
    return (
      <main className="p-4 max-w-2xl mx-auto">
        <p className="text-sm text-red-600" role="alert">
          {err instanceof PermissionError ? err.message : "Onbekende fout"}
        </p>
      </main>
    );
  }
  const canManageInvoices = hasPermission(ctx.role, "MANAGE_INVOICES");

  const supabase = createSupabaseServerClient();

  const { data: tab, error } = await supabase
    .from("open_tabs")
    .select("*, companies(name), departments(name), cost_centers(name), projects(name)")
    .eq("id", params.id)
    .single();

  if (error || !tab) {
    notFound();
  }

  const { data: receiptsRaw } = await supabase
    .from("receipts")
    .select("*, receipt_lines(*), approvals(verification_code, status, approved_by, approved_at)")
    .eq("open_tab_id", params.id)
    .order("created_at", { ascending: false });

  // Guardian Mode-les: het goedkeuringstoken mag niet alleen in tijdelijke
  // client-state leven (dat verdween bij een page-refresh, zie diagnose
  // van v1.34-testronde) — hier halen we het altijd opnieuw uit de database.
  // approvedBy: het meest recente (op approved_at) afgeronde resultaat,
  // los van of er ook nog een pending token is.
  const receipts = receiptsRaw?.map((r: any) => {
    const pendingApproval = r.approvals?.find((a: any) => a.status === "pending");
    const latestResolved = r.approvals
      ?.filter((a: any) => a.status === "approved" || a.status === "rejected")
      .sort((a: any, b: any) => new Date(b.approved_at).getTime() - new Date(a.approved_at).getTime())[0];
    return {
      ...r,
      approval_token: pendingApproval?.verification_code ?? null,
      approved_by: latestResolved?.approved_by ?? null,
    };
  });

  const approvalSettings = tab.company_id
    ? await getApprovalSettings(supabase, tab.company_id)
    : null;

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
        <Row label="Geopend" value={new Date(tab.opened_at).toLocaleString("nl-NL")} />
        {tab.closed_at && (
          <Row label="Gesloten" value={new Date(tab.closed_at).toLocaleString("nl-NL")} />
        )}
      </div>

      {tab.status !== "invoiced" && (
        <TabEditControls
          tabId={tab.id}
          initialTableNumber={tab.table_number ?? ""}
          initialGuestCount={tab.guest_count ? String(tab.guest_count) : ""}
          canDelete={tab.status === "open" && (receipts?.length ?? 0) === 0}
        />
      )}
      {tab.status === "invoiced" && (
        <div className="space-y-2 mb-4 text-sm">
          {tab.table_number && <Row label="Tafel" value={tab.table_number} />}
          {tab.guest_count && <Row label="Aantal personen" value={String(tab.guest_count)} />}
        </div>
      )}

      <ReceiptsSection
        openTabId={params.id}
        initialReceipts={receipts ?? []}
        isInvoiced={tab.status === "invoiced"}
        canAddReceipts={tab.status === "open"}
        approvalMethod={
          approvalSettings?.enabled && approvalSettings.method !== "signature"
            ? approvalSettings.method
            : null
        }
      />

      {tab.status === "open" && (
        <div className="mt-6">
          <CloseTabButton tabId={tab.id} />
        </div>
      )}

      {tab.status === "closed" && canManageInvoices && (
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
      {tab.status === "closed" && !canManageInvoices && (
        <p className="mt-6 text-sm text-neutral-400">
          Deze rekening is klaar om gefactureerd te worden — vraag een collega met
          facturatierechten om dit af te ronden.
        </p>
      )}

      {tab.status === "invoiced" && invoice && canManageInvoices && (
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
