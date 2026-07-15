"use client";

import { useEffect, useState } from "react";

type ReceiptLine = { description: string; quantity: number; unit_price: number; line_total: number };
type Receipt = {
  id: string;
  status: string;
  total: number;
  receipt_number: string | null;
  receipt_date: string;
  receipt_lines: ReceiptLine[];
};

export default function PublicApprovePage({ params }: { params: { token: string } }) {
  const [receipt, setReceipt] = useState<Receipt | null>(null);
  const [companyName, setCompanyName] = useState("");
  const [approvalStatus, setApprovalStatus] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<"approved" | "rejected" | null>(null);

  const [name, setName] = useState("");
  const [showReject, setShowReject] = useState(false);
  const [reason, setReason] = useState("");

  useEffect(() => {
    fetch(`/api/public-approve/${params.token}`)
      .then((r) => r.json())
      .then((body) => {
        if (body.error) {
          setError(body.error);
        } else {
          setReceipt(body.receipt);
          setCompanyName(body.companyName);
          setApprovalStatus(body.approvalStatus);
        }
        setLoading(false);
      })
      .catch(() => {
        setError("Kon gegevens niet laden.");
        setLoading(false);
      });
  }, [params.token]);

  async function handleSubmit(action: "approve" | "reject") {
    if (!name.trim()) {
      setError("Vul je naam in.");
      return;
    }
    setSubmitting(true);
    setError(null);

    const response = await fetch(`/api/public-approve/${params.token}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action, approverName: name.trim(), reason: reason.trim() || undefined }),
    });
    const body = await response.json();
    setSubmitting(false);

    if (!response.ok) {
      setError(body.error || "Actie mislukt.");
      return;
    }

    setDone(action === "approve" ? "approved" : "rejected");
  }

  return (
    <main className="min-h-screen flex items-center justify-center p-4 bg-neutral-50">
      <div className="w-full max-w-sm bg-white rounded-lg border border-neutral-200 p-5">
        <h1 className="text-lg font-semibold mb-1">Polder — Goedkeuring</h1>

        {loading && <p className="text-sm text-neutral-500">Bezig met laden...</p>}

        {error && (
          <p className="text-sm text-red-600" role="alert">
            {error}
          </p>
        )}

        {done === "approved" && (
          <p className="text-sm text-green-700 bg-green-50 border border-green-200 rounded-lg p-3">
            ✓ Goedgekeurd. Je kan dit venster sluiten.
          </p>
        )}
        {done === "rejected" && (
          <p className="text-sm text-amber-700 bg-amber-50 border border-amber-200 rounded-lg p-3">
            Afgewezen — het restaurant is op de hoogte. Je kan dit venster sluiten.
          </p>
        )}

        {!loading && !error && !done && receipt && (
          <>
            <p className="text-sm text-neutral-500 mb-4">{companyName}</p>

            {approvalStatus !== "pending" ? (
              <p className="text-sm text-amber-700 bg-amber-50 border border-amber-200 rounded-lg p-3">
                Deze goedkeuring is al verwerkt.
              </p>
            ) : (
              <>
                <div className="space-y-1 mb-4 text-sm">
                  {receipt.receipt_lines.map((l, i) => (
                    <div key={i} className="flex justify-between">
                      <span>
                        {l.quantity}× {l.description}
                      </span>
                      <span>€{l.line_total.toFixed(2)}</span>
                    </div>
                  ))}
                  <div className="flex justify-between font-semibold pt-2 border-t border-neutral-200">
                    <span>Totaal</span>
                    <span>€{receipt.total.toFixed(2)}</span>
                  </div>
                </div>

                <div className="mb-3">
                  <label className="block text-sm font-medium mb-1">Jouw naam</label>
                  <input
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="Voor- en achternaam"
                    className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
                  />
                </div>

                {!showReject ? (
                  <div className="flex gap-2">
                    <button
                      onClick={() => handleSubmit("approve")}
                      disabled={submitting}
                      className="flex-1 min-h-touch rounded-lg bg-neutral-900 text-white font-medium disabled:opacity-50"
                    >
                      {submitting ? "Bezig..." : "Goedkeuren"}
                    </button>
                    <button
                      onClick={() => setShowReject(true)}
                      disabled={submitting}
                      className="min-h-touch px-4 rounded-lg border border-red-300 text-red-600 text-sm font-medium"
                    >
                      Afwijzen
                    </button>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <label className="block text-sm font-medium">Reden (optioneel)</label>
                    <textarea
                      value={reason}
                      onChange={(e) => setReason(e.target.value)}
                      rows={2}
                      placeholder="Wat klopt er niet?"
                      className="w-full px-3 py-2 rounded-lg border border-neutral-300 bg-white text-sm"
                    />
                    <div className="flex gap-2">
                      <button
                        onClick={() => handleSubmit("reject")}
                        disabled={submitting}
                        className="flex-1 min-h-touch rounded-lg bg-red-600 text-white font-medium disabled:opacity-50"
                      >
                        {submitting ? "Bezig..." : "Bevestig afwijzen"}
                      </button>
                      <button
                        onClick={() => setShowReject(false)}
                        className="min-h-touch px-4 rounded-lg border border-neutral-300 text-sm"
                      >
                        Terug
                      </button>
                    </div>
                  </div>
                )}
              </>
            )}
          </>
        )}
      </div>
    </main>
  );
}
