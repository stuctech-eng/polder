"use client";

import { useState } from "react";

export default function DownloadInvoiceButton({ invoiceId }: { invoiceId: string }) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleDownload() {
    setLoading(true);
    setError(null);

    const response = await fetch(`/api/invoices/${invoiceId}/pdf-url`);
    const body = await response.json();

    setLoading(false);

    if (!response.ok) {
      setError(body.error || "Kon PDF niet ophalen.");
      return;
    }

    window.open(body.url, "_blank");
  }

  return (
    <div>
      <button
        onClick={handleDownload}
        disabled={loading}
        className="min-h-touch px-4 rounded-lg border border-neutral-300 text-sm font-medium disabled:opacity-50"
      >
        {loading ? "Bezig..." : "Download factuur (PDF)"}
      </button>
      {error && (
        <p className="text-sm text-red-600 mt-2" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
