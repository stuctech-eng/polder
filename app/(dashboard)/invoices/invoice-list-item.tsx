"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import DownloadInvoiceButton from "../open-tabs/[id]/download-invoice-button";

type Invoice = {
  id: string;
  invoice_number: string;
  status: string;
  total: number;
  due_at: string;
  companies?: { name: string } | null;
};

const STATUS_LABELS: Record<string, { label: string; className: string }> = {
  draft: { label: "Concept", className: "bg-neutral-100 text-neutral-600" },
  sent: { label: "Verzonden", className: "bg-blue-50 text-blue-700" },
  paid: { label: "Betaald", className: "bg-green-50 text-green-700" },
  overdue: { label: "Te laat", className: "bg-red-50 text-red-700" },
};

export function InvoiceListItem({
  invoice: initialInvoice,
  initialTotalPaid,
}: {
  invoice: Invoice;
  initialTotalPaid: number;
}) {
  const router = useRouter();
  const [invoice, setInvoice] = useState(initialInvoice);
  const [totalPaid, setTotalPaid] = useState(initialTotalPaid);
  const [showPaymentForm, setShowPaymentForm] = useState(false);
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const remaining = Math.max(0, invoice.total - totalPaid);
  const statusInfo = STATUS_LABELS[invoice.status] ?? {
    label: invoice.status,
    className: "bg-neutral-100 text-neutral-600",
  };

  async function handleMarkSent() {
    setLoading(true);
    setError(null);
    const response = await fetch(`/api/invoices/${invoice.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "sent" }),
    });
    setLoading(false);
    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon status niet wijzigen.");
      return;
    }
    setInvoice((prev) => ({ ...prev, status: "sent" }));
    router.refresh();
  }

  async function handleAddPayment(e: React.FormEvent) {
    e.preventDefault();
    const parsedAmount = parseFloat(amount.replace(",", "."));
    if (!parsedAmount || parsedAmount <= 0) {
      setError("Vul een geldig bedrag in.");
      return;
    }
    setLoading(true);
    setError(null);

    const response = await fetch(`/api/invoices/${invoice.id}/payments`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ amount: parsedAmount, method: method || undefined }),
    });
    const body = await response.json();
    setLoading(false);

    if (!response.ok) {
      setError(body.error || "Kon betaling niet registreren.");
      return;
    }

    setTotalPaid(body.totalPaid);
    if (body.isFullyPaid) {
      setInvoice((prev) => ({ ...prev, status: "paid" }));
    } else if (invoice.status === "draft") {
      setInvoice((prev) => ({ ...prev, status: "sent" }));
    }
    setShowPaymentForm(false);
    setAmount("");
    setMethod("");
    router.refresh();
  }

  return (
    <li className="px-4 py-3 rounded-lg border border-neutral-200 bg-white">
      <div className="flex justify-between items-start">
        <div>
          <div className="font-medium">{invoice.invoice_number}</div>
          <div className="text-sm text-neutral-500">{invoice.companies?.name ?? "Onbekend bedrijf"}</div>
          <div className="text-xs text-neutral-400 mt-1">
            Vervaldatum: {new Date(invoice.due_at).toLocaleDateString("nl-NL")}
          </div>
        </div>
        <div className="text-right">
          <div className="font-medium">€{invoice.total.toFixed(2)}</div>
          <span className={`text-xs px-2 py-1 rounded-full font-medium inline-block mt-1 ${statusInfo.className}`}>
            {statusInfo.label}
          </span>
        </div>
      </div>

      <div className="mt-2">
        <DownloadInvoiceButton invoiceId={invoice.id} />
      </div>

      {invoice.status === "paid" ? (
        <p className="text-xs text-green-700 mt-2">✓ Volledig betaald</p>
      ) : (
        <div className="mt-2">
          {totalPaid > 0 && (
            <p className="text-xs text-neutral-500 mb-1">
              €{totalPaid.toFixed(2)} betaald, nog €{remaining.toFixed(2)} openstaand
            </p>
          )}

          {!showPaymentForm ? (
            <div className="flex gap-3">
              {invoice.status === "draft" && (
                <button onClick={handleMarkSent} disabled={loading} className="text-xs text-neutral-600 underline">
                  Markeer als verzonden
                </button>
              )}
              <button
                onClick={() => {
                  setAmount(String(remaining));
                  setShowPaymentForm(true);
                }}
                className="text-xs text-neutral-900 underline font-medium"
              >
                Betaling registreren
              </button>
            </div>
          ) : (
            <form onSubmit={handleAddPayment} className="flex gap-2 items-center flex-wrap mt-1">
              <input
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="Bedrag"
                inputMode="decimal"
                className="w-24 min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-xs"
              />
              <input
                value={method}
                onChange={(e) => setMethod(e.target.value)}
                placeholder="Methode (optioneel)"
                className="flex-1 min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-xs min-w-0"
              />
              <button
                type="submit"
                disabled={loading}
                className="min-h-touch px-3 rounded-lg bg-neutral-900 text-white text-xs font-medium"
              >
                {loading ? "..." : "Opslaan"}
              </button>
              <button type="button" onClick={() => setShowPaymentForm(false)} className="text-xs text-neutral-500">
                Annuleren
              </button>
            </form>
          )}
        </div>
      )}
      {error && <p className="text-xs text-red-600 mt-1">{error}</p>}
    </li>
  );
}
