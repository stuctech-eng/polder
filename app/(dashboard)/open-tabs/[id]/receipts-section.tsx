"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type ReceiptLine = {
  description: string;
  quantityText: string;
  unitPriceText: string;
  vatRate: number;
};

function parseDecimal(text: string): number {
  const normalized = text.replace(",", ".").trim();
  const parsed = parseFloat(normalized);
  return Number.isNaN(parsed) ? 0 : parsed;
}
type Receipt = {
  id: string;
  receipt_number: string | null;
  status: string;
  total: number;
  subtotal: number;
  vat_amount: number;
  receipt_date: string;
  receipt_lines: { description: string; quantity: number; unit_price: number; line_total: number }[];
  approval_token?: string | null;
  approved_by?: string | null;
};

const VAT_RATES = [
  { label: "9% (laag)", value: 9 },
  { label: "21% (hoog)", value: 21 },
  { label: "0%", value: 0 },
];

export function ReceiptsSection({
  openTabId,
  initialReceipts,
  isInvoiced = false,
  canAddReceipts = true,
  approvalMethod = null,
}: {
  openTabId: string;
  initialReceipts: Receipt[];
  isInvoiced?: boolean;
  canAddReceipts?: boolean;
  approvalMethod?: "pin" | "restaurant_confirms" | "email" | "qr" | null;
}) {
  const router = useRouter();
  const [receipts, setReceipts] = useState(initialReceipts);
  const [showForm, setShowForm] = useState(false);
  const [receiptNumber, setReceiptNumber] = useState("");
  const [lines, setLines] = useState<ReceiptLine[]>([
    { description: "", quantityText: "1", unitPriceText: "", vatRate: 9 },
  ]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  function updateLine(index: number, updates: Partial<ReceiptLine>) {
    setLines((prev) => prev.map((line, i) => (i === index ? { ...line, ...updates } : line)));
  }

  function addLine() {
    setLines((prev) => [...prev, { description: "", quantityText: "1", unitPriceText: "", vatRate: 9 }]);
  }

  function removeLine(index: number) {
    setLines((prev) => prev.filter((_, i) => i !== index));
  }

  const estimatedTotal = lines.reduce((sum, l) => {
    const quantity = parseDecimal(l.quantityText);
    const unitPrice = parseDecimal(l.unitPriceText);
    const lineSubtotal = quantity * unitPrice;
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
        lines: lines.map((l) => ({
          description: l.description,
          quantity: parseDecimal(l.quantityText) || 1,
          unitPrice: parseDecimal(l.unitPriceText),
          vatRate: l.vatRate,
        })),
      }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon bon niet toevoegen.");
      return;
    }

    const { receipt, approvalToken, approvalWarning } = await response.json();
    setReceipts((prev) => [{ ...receipt, approval_token: approvalToken }, ...prev]);
    setReceiptNumber("");
    setLines([{ description: "", quantityText: "1", unitPriceText: "", vatRate: 9 }]);
    setShowForm(false);
    if (approvalWarning) {
      setError(approvalWarning);
    }
    router.refresh();
  }

  return (
    <div className="border-t border-neutral-200 pt-4 mt-4">
      <div className="flex items-center justify-between mb-2">
        <h2 className="text-sm font-semibold text-neutral-700">Bonnen</h2>
        {canAddReceipts && (
          <button
            onClick={() => setShowForm((v) => !v)}
            className="min-h-touch px-3 rounded-lg bg-neutral-900 text-white text-sm font-medium"
          >
            {showForm ? "Annuleren" : "+ Bon toevoegen"}
          </button>
        )}
      </div>

      {!canAddReceipts && (
        <p className="text-xs text-neutral-400 mb-2">
          {isInvoiced
            ? "Deze rekening is al gefactureerd — er kunnen geen bonnen meer toegevoegd worden."
            : "Deze rekening is gesloten — er kunnen geen bonnen meer toegevoegd worden."}
        </p>
      )}

      <details className="mb-3 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-3">
        <summary className="px-3 py-2 text-sm font-medium text-neutral-700 cursor-pointer">
          Hoe werkt dit? ℹ️
        </summary>
        <div className="px-3 text-sm text-neutral-600 space-y-1">
          <p>Vul per product een regel in: aantal, prijs per stuk (excl. BTW), en het BTW-tarief. Je mag prijzen met komma of punt intikken, bijv. 12,50 of 12.50.</p>
          <p>Voorbeeld: 2× Lunch à €12,50, 9% BTW → totaal €27,25.</p>
          <p>Meerdere producten? Voeg een extra regel toe met "+ Productregel toevoegen".</p>
        </div>
      </details>

      {receipts.length === 0 && !showForm && (
        <p className="text-sm text-neutral-400 py-2">Nog geen bonnen gekoppeld.</p>
      )}

      <ul className="space-y-2 mb-3">
        {receipts.map((r) => (
          <ReceiptItem
            key={r.id}
            receipt={r}
            isInvoiced={isInvoiced}
            approvalMethod={approvalMethod}
            onDeleted={() => setReceipts((prev) => prev.filter((x) => x.id !== r.id))}
            onUpdated={(updated) =>
              setReceipts((prev) => prev.map((x) => (x.id === updated.id ? { ...x, ...updated } : x)))
            }
          />
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
            <div className="flex gap-2 text-xs text-neutral-500 px-1">
              <span className="flex-1">Product</span>
              <span className="w-14 text-center">Aantal</span>
              <span className="w-16 text-center">Prijs (€)</span>
              <span className="w-[76px] text-center">BTW</span>
            </div>
            {lines.map((line, i) => (
              <div key={i} className="flex gap-2 items-start">
                <input
                  value={line.description}
                  onChange={(e) => updateLine(i, { description: e.target.value })}
                  placeholder="bijv. Lunch"
                  className="flex-1 min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-sm min-w-0"
                />
                <input
                  type="text"
                  inputMode="decimal"
                  value={line.quantityText}
                  onChange={(e) => updateLine(i, { quantityText: e.target.value })}
                  placeholder="1"
                  className="w-14 min-h-touch px-1 rounded-lg border border-neutral-300 bg-white text-sm text-center"
                  aria-label="Aantal"
                />
                <input
                  type="text"
                  inputMode="decimal"
                  value={line.unitPriceText}
                  onChange={(e) => updateLine(i, { unitPriceText: e.target.value })}
                  placeholder="12,50"
                  className="w-16 min-h-touch px-1 rounded-lg border border-neutral-300 bg-white text-sm text-center"
                  aria-label="Prijs per stuk in euro's, met komma of punt"
                />
                <select
                  value={line.vatRate}
                  onChange={(e) => updateLine(i, { vatRate: Number(e.target.value) })}
                  className="w-[76px] min-h-touch px-1 rounded-lg border border-neutral-300 bg-white text-xs"
                  aria-label="BTW-tarief"
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

function ReceiptItem({
  receipt,
  isInvoiced,
  approvalMethod,
  onDeleted,
  onUpdated,
}: {
  receipt: Receipt;
  isInvoiced: boolean;
  approvalMethod: "pin" | "restaurant_confirms" | "email" | "qr" | null;
  onDeleted: () => void;
  onUpdated: (updated: Partial<Receipt> & { id: string }) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [receiptNumber, setReceiptNumber] = useState(receipt.receipt_number ?? "");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSave() {
    setLoading(true);
    setError(null);

    const response = await fetch(`/api/receipts/${receipt.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ receiptNumber: receiptNumber || undefined }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon bon niet bijwerken.");
      return;
    }

    onUpdated({ id: receipt.id, receipt_number: receiptNumber || null });
    setEditing(false);
  }

  async function handleDelete() {
    if (!confirm("Deze bon definitief verwijderen?")) return;
    setLoading(true);
    setError(null);

    const response = await fetch(`/api/receipts/${receipt.id}`, { method: "DELETE" });
    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon bon niet verwijderen.");
      return;
    }

    onDeleted();
  }

  return (
    <li className="px-3 py-2 rounded-lg bg-neutral-50 text-sm">
      <div className="flex justify-between font-medium items-center">
        {editing ? (
          <input
            value={receiptNumber}
            onChange={(e) => setReceiptNumber(e.target.value)}
            placeholder="Bonnummer"
            className="flex-1 min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-sm mr-2"
          />
        ) : (
          <span>
            {receipt.receipt_number || "Bon zonder nummer"}
            {receipt.status === "pending_approval" && (
              <span className="ml-2 text-xs font-normal text-amber-600">wacht op goedkeuring</span>
            )}
            {receipt.status === "locked" && (
              <span className="ml-2 text-xs font-normal text-green-700">
                ✓ goedgekeurd{receipt.approved_by ? ` door ${receipt.approved_by}` : ""}
              </span>
            )}
          </span>
        )}
        <span>€{receipt.total.toFixed(2)}</span>
      </div>
      <div className="text-neutral-500 text-xs mt-1">
        {receipt.receipt_lines.map((l, i) => (
          <div key={i}>
            {l.quantity}× {l.description} — €{l.line_total.toFixed(2)}
          </div>
        ))}
      </div>

      {receipt.status === "pending_approval" && (
        <ApprovalBlock
          receiptId={receipt.id}
          method={approvalMethod}
          approvalToken={receipt.approval_token ?? null}
          onApproved={(status, approvedBy) => onUpdated({ id: receipt.id, status, approved_by: approvedBy })}
        />
      )}

      {!isInvoiced && receipt.status !== "locked" && receipt.status !== "pending_approval" && (
        <div className="flex gap-3 mt-2">
          {editing ? (
            <>
              <button
                onClick={handleSave}
                disabled={loading}
                className="text-xs text-neutral-900 font-medium underline"
              >
                Opslaan
              </button>
              <button
                onClick={() => setEditing(false)}
                className="text-xs text-neutral-500"
              >
                Annuleren
              </button>
            </>
          ) : (
            <>
              <button
                onClick={() => setEditing(true)}
                className="text-xs text-neutral-600 underline"
              >
                Bewerken
              </button>
              <button
                onClick={handleDelete}
                disabled={loading}
                className="text-xs text-red-600 underline"
              >
                Verwijderen
              </button>
            </>
          )}
        </div>
      )}
      {error && <p className="text-xs text-red-600 mt-1">{error}</p>}
    </li>
  );
}

/**
 * Kent alleen de methode-naam om het juiste invoerveld te tonen — geen
 * providerlogica (PIN-hashing, etc.) zit hier, dat blijft server-side in de
 * Approval Service (klant-instructie, sectie 10.7).
 */
function ApprovalBlock({
  receiptId,
  method,
  approvalToken,
  onApproved,
}: {
  receiptId: string;
  method: "pin" | "restaurant_confirms" | "email" | "qr" | null;
  approvalToken: string | null;
  onApproved: (status: string, approvedBy?: string) => void;
}) {
  const [pin, setPin] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleApprove(e?: React.FormEvent) {
    e?.preventDefault();
    setLoading(true);
    setError(null);

    const response = await fetch(`/api/receipts/${receiptId}/approve`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(method === "pin" ? { credential: pin } : {}),
    });

    const body = await response.json();
    setLoading(false);

    if (!response.ok) {
      setError(body.error || "Goedkeuring mislukt.");
      return;
    }

    onApproved(body.status, body.approvedBy);
  }

  if (method === "pin") {
    return (
      <form onSubmit={handleApprove} className="flex gap-2 mt-2 items-center">
        <input
          type="password"
          inputMode="numeric"
          value={pin}
          onChange={(e) => setPin(e.target.value)}
          placeholder="PIN"
          className="w-20 min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-sm"
        />
        <button
          type="submit"
          disabled={loading || !pin}
          className="min-h-touch px-3 rounded-lg bg-neutral-900 text-white text-xs font-medium disabled:opacity-50"
        >
          {loading ? "..." : "Goedkeuren"}
        </button>
        {error && <p className="text-xs text-red-600">{error}</p>}
      </form>
    );
  }

  if (method === "email") {
    return (
      <p className="mt-2 text-xs text-neutral-500">
        📧 Goedkeuringsmail verstuurd — wacht tot de manager de link opent.
      </p>
    );
  }

  if (method === "qr" && approvalToken) {
    const approveUrl =
      typeof window !== "undefined"
        ? `${window.location.origin}/approve/${approvalToken}`
        : `/approve/${approvalToken}`;
    const qrImageUrl = `https://api.qrserver.com/v1/create-qr-code/?size=140x140&data=${encodeURIComponent(approveUrl)}`;
    return (
      <div className="mt-2">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={qrImageUrl} alt="Scan om goed te keuren" width={140} height={140} className="rounded-lg border border-neutral-200" />
        <p className="text-xs text-neutral-500 mt-1">Scan om goed te keuren, of:</p>
        <a href={approveUrl} target="_blank" rel="noopener noreferrer" className="text-xs text-blue-600 underline break-all">
          {approveUrl}
        </a>
      </div>
    );
  }

  // restaurant_confirms (of onbekende/niet-geconfigureerde methode: toon
  // toch de knop, de server valideert alsnog of dit toegestaan is)
  return (
    <div className="mt-2">
      <button
        onClick={() => handleApprove()}
        disabled={loading}
        className="min-h-touch px-3 rounded-lg bg-neutral-900 text-white text-xs font-medium disabled:opacity-50"
      >
        {loading ? "Bezig..." : "Goedkeuren"}
      </button>
      {error && <p className="text-xs text-red-600 mt-1">{error}</p>}
    </div>
  );
}
