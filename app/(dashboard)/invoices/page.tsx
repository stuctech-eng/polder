import { createSupabaseServerClient } from "@/lib/supabase/server";
import DownloadInvoiceButton from "../open-tabs/[id]/download-invoice-button";

export default async function InvoicesPage() {
  const supabase = createSupabaseServerClient();
  const { data: invoices, error } = await supabase
    .from("invoices")
    .select("*, companies(name)")
    .order("issued_at", { ascending: false });

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <h1 className="text-xl font-semibold mb-4">Facturen</h1>

      {error && (
        <p className="text-sm text-red-600 mb-4" role="alert">
          Fout bij ophalen: {error.message}
        </p>
      )}

      <ul className="space-y-2">
        {invoices?.map((invoice: any) => (
          <li key={invoice.id} className="px-4 py-3 rounded-lg border border-neutral-200 bg-white">
            <div className="flex justify-between items-start">
              <div>
                <div className="font-medium">{invoice.invoice_number}</div>
                <div className="text-sm text-neutral-500">
                  {invoice.companies?.name ?? "Onbekend bedrijf"}
                </div>
                <div className="text-xs text-neutral-400 mt-1">
                  Vervaldatum: {new Date(invoice.due_at).toLocaleDateString("nl-NL")}
                </div>
              </div>
              <div className="text-right">
                <div className="font-medium">€{Number(invoice.total).toFixed(2)}</div>
                <div className="text-xs text-neutral-400 capitalize">{invoice.status}</div>
              </div>
            </div>
            <div className="mt-2">
              <DownloadInvoiceButton invoiceId={invoice.id} />
            </div>
          </li>
        ))}
        {!invoices?.length && !error && (
          <p className="text-neutral-500 text-sm py-8 text-center">
            Nog geen facturen. Sluit een rekening en genereer de eerste factuur.
          </p>
        )}
      </ul>
    </main>
  );
}
