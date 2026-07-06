"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function GenerateInvoiceButton({ openTabId }: { openTabId: string }) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [warning, setWarning] = useState<string | null>(null);

  async function handleGenerate() {
    setLoading(true);
    setError(null);
    setWarning(null);

    const response = await fetch(`/api/open-tabs/${openTabId}/generate-invoice`, {
      method: "POST",
    });

    const body = await response.json();
    setLoading(false);

    if (!response.ok) {
      setError(body.error || "Kon factuur niet genereren.");
      return;
    }

    if (body.warning) {
      setWarning(body.warning);
    }

    router.refresh();
  }

  return (
    <div>
      <button
        onClick={handleGenerate}
        disabled={loading}
        className="w-full min-h-touch rounded-lg bg-neutral-900 text-white font-medium disabled:opacity-50"
      >
        {loading ? "Bezig met factureren..." : "Factuur genereren"}
      </button>
      {error && (
        <p className="text-sm text-red-600 mt-2" role="alert">
          {error}
        </p>
      )}
      {warning && (
        <p className="text-sm text-amber-600 mt-2" role="alert">
          {warning}
        </p>
      )}
    </div>
  );
}
