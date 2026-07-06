"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type ReceiptLine = { description: string; quantity: number; unitPrice: number; vatRate: number };
type Receipt = {
  id: string;
  receipt_number: string | null;
  total: number;
  subtotal: number;
  vat_amount: number;
  receipt_date: string;
  receipt_lines: { description: string; quantity: number; unit_price: number; line_total: number }[];
};

const VAT_RATES = [
  { label: "9% (laag)", value: 9 },
  { label: "21% (hoog)", value: 21 },
  { label: "0%", value: 0 },
];

export function ReceiptsSection({
  openTabId,
  initialReceipts,
}: {
  openTabId: string;
  initialReceipts: Receipt[];
}) {
  const router = useRouter();
  const [receipts, setReceipts] = useState(initialReceipts);
  const [showForm, setShowForm] = useState(false);
  const [receiptNumber, setReceiptNumber] = useState("");
  const [lines, setLines] = useState<ReceiptLine[]>([
    { description: "", quantity: 1, unitPrice: 0, vatRate: 9 },
  ]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  function updateLine(index: number, updates: Partial<ReceiptLine>) {
    setLines((prev) => prev.map((line, i) => (i === index ? { ...line, ...updates } : line)));
  }

  function addLine() {
    setLines((prev) => [...prev, { description: "", quantity: 1, unitPrice: 0, vatRate: 9 }]);
  }

  function removeLine(index: number) {
    setLines((prev) => prev.filter((_, i) => i !== index));
  }

  const estimatedTotal = lines.reduce((sum, l) => {
    const lineSubtotal = l.quantity * l.unitPrice;
    return sum + lineSubtotal + lineSubtotal * (l.vatRate / 100);
  }, 0);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);

    const response = await fetch(`/api/open-tabs/${openTabId}/receipts`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        receiptNumber: receiptNumber || undefined,
        lines,
      }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon bon niet toevoegen.");
      return;
    }

    const { receipt } = await response.json();
    setReceipts((prev) => [receipt, ...prev]);
    setReceiptNumber("");
    setLines([{ description: "", quantity: 1, unitPrice: 0, vatRate: 9 }]);
    setShowForm(false);
    router.refresh();
  }

  return (
    <div className="border-t border-neutral-200 pt-4 mt-4">
      <div className="flex items-center justify-between mb-2">
        <h2 className="text-sm font-semibold text-neutral-700">Bonnen</h2>
        <button
          onClick={() => setShowForm((v) => !v)}
          className="min-h-touch px-3 rounded-lg bg-neutral-900 text-white text-sm font-medium"
        >
          {showForm ? "Annuleren" : "+ Bon toevoegen"}
        </button>
      </div>

      {receipts.length === 0 && !showForm && (
        <p className="text-sm text-neutral-400 py-2">Nog geen bonnen gekoppeld.</p>
      )}

      <ul className="space-y-2 mb-3">
        {receipts.map((r) => (
          <li key={r.id} className="px-3 py-2 rounded-lg bg-neutral-50 text-sm">
            <div className="flex justify-between font-medium">
              <span>{r.receipt_number || "Bon zonder nummer"}</span>
              <span>€{r.total.toFixed(2)}</span>
            </div>
            <div className="text-neutral-500 text-xs mt-1">
              {r.receipt_lines.map((l, i) => (
                <div key={i}>
                  {l.quantity}× {l.description} — €{l.line_total.toFixed(2)}
                </div>
              ))}
            </div>
          </li>
        ))}
      </ul>

      {showForm && (
        <form onSubmit={handleSubmit} className="space-y-3 bg-neutral-50 rounded-lg p-3">
          <input
            value={receiptNumber}
            onChange={(e) => setReceiptNumber(e.target.value)}
            placeholder="Bonnummer (optioneel)"
            className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
          />

          <div className="space-y-2">
            {lines.map((line, i) => (
              <div key={i} className="flex gap-2 items-start">
                <input
                  value={line.description}
                  onChange={(e) => updateLine(i, { description: e.target.value })}
                  placeholder="Product"
                  className="flex-1 min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-sm min-w-0"
                />
                <input
                  type="number"
                  min={0.01}
                  step="0.01"
                  value={line.quantity}
                  onChange={(e) => updateLine(i, { quantity: Number(e.target.value) })}
                  className="w-14 min-h-touch px-1 rounded-lg border border-neutral-300 bg-white text-sm text-center"
                  aria-label="Aantal"
                />
                <input
                  type="number"
                  min={0}
                  step="0.01"
                  value={line.unitPrice}
                  onChange={(e) => updateLine(i, { unitPrice: Number(e.target.value) })}
                  className="w-16 min-h-touch px-1 rounded-lg border border-neutral-300 bg-white text-sm text-center"
                  aria-label="Prijs"
                />
                <select
                  value={line.vatRate}
                  onChange={(e) => updateLine(i, { vatRate: Number(e.target.value) })}
                  className="min-h-touch px-1 rounded-lg border border-neutral-300 bg-white text-xs"
                  aria-label="BTW"
                >
                  {VAT_RATES.map((v) => (
                    <option key={v.value} value={v.value}>
                      {v.label}
                    </option>
                  ))}
                </select>
                {lines.length > 1 && (
                  <button
                    type="button"
                    onClick={() => removeLine(i)}
                    className="min-h-touch min-w-touch flex items-center justify-center text-red-500 text-sm"
                    aria-label="Regel verwijderen"
                  >
                    ✕
                  </button>
                )}
              </div>
            ))}
          </div>

          <button
            type="button"
            onClick={addLine}
            className="text-sm text-neutral-600 underline"
          >
            + Productregel toevoegen
          </button>

          <div className="flex justify-between text-sm font-medium pt-2 border-t border-neutral-200">
            <span>Geschat totaal (incl. BTW)</span>
            <span>€{estimatedTotal.toFixed(2)}</span>
          </div>

          {error && (
            <p className="text-sm text-red-600" role="alert">
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full min-h-touch rounded-lg bg-neutral-900 text-white font-medium disabled:opacity-50"
          >
            {loading ? "Bezig..." : "Bon opslaan"}
          </button>
        </form>
      )}
    </div>
  );
}
