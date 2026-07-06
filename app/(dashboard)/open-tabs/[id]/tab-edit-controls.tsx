"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function TabEditControls({
  tabId,
  initialTableNumber,
  initialGuestCount,
  canDelete,
}: {
  tabId: string;
  initialTableNumber: string;
  initialGuestCount: string;
  canDelete: boolean;
}) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [tableNumber, setTableNumber] = useState(initialTableNumber);
  const [guestCount, setGuestCount] = useState(initialGuestCount);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSave() {
    setLoading(true);
    setError(null);

    const response = await fetch(`/api/open-tabs/${tabId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        tableNumber: tableNumber || undefined,
        guestCount: guestCount ? Number(guestCount) : undefined,
      }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon niet opslaan.");
      return;
    }

    setEditing(false);
    router.refresh();
  }

  async function handleDelete() {
    if (!confirm("Deze lege rekening verwijderen?")) return;
    setLoading(true);
    setError(null);

    const response = await fetch(`/api/open-tabs/${tabId}`, { method: "DELETE" });
    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon rekening niet verwijderen.");
      return;
    }

    router.push("/open-tabs");
    router.refresh();
  }

  if (!editing) {
    return (
      <div className="space-y-2 mb-4 text-sm">
        <div className="flex justify-between px-4 py-2 rounded-lg bg-neutral-50">
          <span className="text-neutral-500">Tafel</span>
          <span className="font-medium">{initialTableNumber || "-"}</span>
        </div>
        <div className="flex justify-between px-4 py-2 rounded-lg bg-neutral-50">
          <span className="text-neutral-500">Aantal personen</span>
          <span className="font-medium">{initialGuestCount || "-"}</span>
        </div>
        <div className="flex gap-3">
          <button onClick={() => setEditing(true)} className="text-xs text-neutral-600 underline">
            Bewerken
          </button>
          {canDelete && (
            <button onClick={handleDelete} disabled={loading} className="text-xs text-red-600 underline">
              Rekening verwijderen
            </button>
          )}
        </div>
        {error && <p className="text-xs text-red-600">{error}</p>}
      </div>
    );
  }

  return (
    <div className="space-y-2 mb-4 bg-neutral-50 rounded-lg p-3">
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-xs text-neutral-500 mb-1">Tafel</label>
          <input
            value={tableNumber}
            onChange={(e) => setTableNumber(e.target.value)}
            className="w-full min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-sm"
          />
        </div>
        <div>
          <label className="block text-xs text-neutral-500 mb-1">Aantal personen</label>
          <input
            type="number"
            min={1}
            value={guestCount}
            onChange={(e) => setGuestCount(e.target.value)}
            className="w-full min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-sm"
          />
        </div>
      </div>
      {error && <p className="text-xs text-red-600">{error}</p>}
      <div className="flex gap-3">
        <button
          onClick={handleSave}
          disabled={loading}
          className="min-h-touch px-3 rounded-lg bg-neutral-900 text-white text-xs font-medium"
        >
          Opslaan
        </button>
        <button onClick={() => setEditing(false)} className="text-xs text-neutral-500">
          Annuleren
        </button>
      </div>
    </div>
  );
}
