"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function CloseTabButton({ tabId }: { tabId: string }) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleClose() {
    setLoading(true);
    setError(null);

    const response = await fetch(`/api/open-tabs/${tabId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "closed" }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon rekening niet sluiten.");
      return;
    }

    router.refresh();
  }

  return (
    <div>
      <button
        onClick={handleClose}
        disabled={loading}
        className="w-full min-h-touch rounded-lg bg-neutral-900 text-white font-medium disabled:opacity-50"
      >
        {loading ? "Bezig..." : "Rekening sluiten"}
      </button>
      {error && (
        <p className="text-sm text-red-600 mt-2" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
