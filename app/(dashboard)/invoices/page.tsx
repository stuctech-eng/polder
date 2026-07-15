import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { InvoiceListItem } from "./invoice-list-item";

export default async function InvoicesPage() {
  try {
    await requireRole("MANAGE_INVOICES");
  } catch (err) {
    return (
      <main className="p-4 max-w-2xl mx-auto">
        <h1 className="text-xl font-semibold mb-4">Facturen</h1>
        <p className="text-sm text-red-600" role="alert">
          {err instanceof PermissionError ? err.message : "Onbekende fout"}
        </p>
      </main>
    );
  }

  const supabase = createSupabaseServerClient();
  const { data: invoices, error } = await supabase
    .from("invoices")
    .select("*, companies(name), payments(amount)")
    .order("issued_at", { ascending: false });

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <h1 className="text-xl font-semibold mb-4">Facturen</h1>

      <details className="mb-4 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-3">
        <summary className="px-3 py-2 text-sm font-medium text-neutral-700 cursor-pointer">
          Hoe werkt dit? ℹ️
        </summary>
        <div className="px-3 text-sm text-neutral-600 space-y-1">
          <p>
            <strong>Concept</strong>: net gegenereerd. <strong>Verzonden</strong>: markeer
            zelf zodra de klant de factuur heeft ontvangen. <strong>Betaald</strong>: gaat
            automatisch aan zodra het geregistreerde betalingsbedrag de factuur volledig
            dekt — gedeeltelijke betalingen mogen ook, dan blijft de status "Verzonden" met
            het openstaande bedrag zichtbaar.
          </p>
        </div>
      </details>

      {error && (
        <p className="text-sm text-red-600 mb-4" role="alert">
          Fout bij ophalen: {error.message}
        </p>
      )}

      <ul className="space-y-2">
        {invoices?.map((invoice: any) => {
          const totalPaid = (invoice.payments ?? []).reduce(
            (sum: number, p: any) => sum + Number(p.amount),
            0
          );
          return (
            <InvoiceListItem
              key={invoice.id}
              invoice={{ ...invoice, total: Number(invoice.total) }}
              initialTotalPaid={totalPaid}
            />
          );
        })}
        {!invoices?.length && !error && (
          <p className="text-neutral-500 text-sm py-8 text-center">
            Nog geen facturen. Sluit een rekening en genereer de eerste factuur.
          </p>
        )}
      </ul>
    </main>
  );
}
