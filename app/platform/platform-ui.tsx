"use client";

import { useState } from "react";
import type { PlatformLogEntry, PlatformRestaurant } from "@/lib/platform/platform-service";

const ACTION_LABELS: Record<PlatformLogEntry["action"], string> = {
  restaurant_aangemaakt: "Restaurant aangemaakt",
  restaurant_aan: "Restaurant aangezet",
  restaurant_uit: "Restaurant uitgezet",
  eigenaar_uitgenodigd: "Eigenaar uitgenodigd",
};

async function readError(response: Response, fallback: string) {
  const body = await response.json().catch(() => ({}));
  return (body.error as string) || `${fallback} (HTTP ${response.status})`;
}

export default function PlatformUI({
  initialRestaurants,
  initialLog,
}: {
  initialRestaurants: PlatformRestaurant[];
  initialLog: PlatformLogEntry[];
}) {
  const [restaurants, setRestaurants] = useState(initialRestaurants);
  const [log, setLog] = useState(initialLog);
  const [error, setError] = useState<string | null>(null);

  async function reload() {
    const [r, l] = await Promise.all([fetch("/api/platform/restaurants"), fetch("/api/platform/log")]);
    if (!r.ok) return setError(await readError(r, "Restaurants laden mislukt"));
    if (!l.ok) return setError(await readError(l, "Logboek laden mislukt"));
    setRestaurants((await r.json()).restaurants);
    setLog((await l.json()).log);
  }

  return (
    <main className="p-4 max-w-2xl mx-auto pb-[calc(1rem+env(safe-area-inset-bottom))]">
      <h1 className="text-xl font-semibold mb-1">Platformbeheer</h1>
      <p className="text-sm text-neutral-500 mb-4">
        Restaurants aanmaken, aan- of uitzetten en de eerste eigenaar uitnodigen. Restaurantinhoud (bonnen, facturen,
        omzet) is hier bewust niet zichtbaar.
      </p>

      {error && (
        <p className="text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg p-3 mb-4" role="alert">
          {error}
        </p>
      )}

      <NewRestaurantForm onDone={reload} onError={setError} />

      <h2 className="text-base font-semibold mt-6 mb-2">Restaurants ({restaurants.length})</h2>
      <ul className="space-y-3">
        {restaurants.map((r) => (
          <RestaurantCard key={r.id} restaurant={r} onDone={reload} onError={setError} />
        ))}
      </ul>

      <h2 className="text-base font-semibold mt-6 mb-2">Logboek</h2>
      {log.length === 0 ? (
        <p className="text-sm text-neutral-500">Nog geen beheeracties.</p>
      ) : (
        <ul className="space-y-2">
          {log.map((entry) => (
            <li key={entry.id} className="text-sm border-b border-neutral-100 pb-2">
              <div className="font-medium">
                {ACTION_LABELS[entry.action] ?? entry.action}
                {entry.restaurantName ? ` — ${entry.restaurantName}` : ""}
              </div>
              <div className="text-neutral-500">
                {new Date(entry.createdAt).toLocaleString("nl-NL", { timeZone: "Europe/Amsterdam" })}
                {entry.adminEmail ? ` · ${entry.adminEmail}` : ""}
                {typeof entry.details.email === "string" ? ` · ${entry.details.email}` : ""}
              </div>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}

function NewRestaurantForm({ onDone, onError }: { onDone: () => Promise<void>; onError: (m: string | null) => void }) {
  const [name, setName] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    onError(null);
    setLoading(true);
    const response = await fetch("/api/platform/restaurants", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    });
    setLoading(false);
    if (!response.ok) return onError(await readError(response, "Restaurant aanmaken mislukt"));
    setName("");
    await onDone();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3 bg-neutral-50 rounded-lg p-3">
      <input
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Naam nieuw restaurant"
        required
        className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
      />
      <button
        type="submit"
        disabled={loading}
        className="w-full min-h-touch rounded-lg bg-neutral-900 text-white text-sm font-medium disabled:opacity-50"
      >
        {loading ? "Bezig..." : "Restaurant aanmaken"}
      </button>
    </form>
  );
}

function RestaurantCard({
  restaurant,
  onDone,
  onError,
}: {
  restaurant: PlatformRestaurant;
  onDone: () => Promise<void>;
  onError: (m: string | null) => void;
}) {
  const [loading, setLoading] = useState(false);
  const [showInvite, setShowInvite] = useState(false);

  async function toggle() {
    const next = !restaurant.isActive;
    const question = next
      ? `${restaurant.name} weer aanzetten?`
      : `${restaurant.name} uitzetten? Niemand van dit restaurant kan dan nog iets zien of wijzigen.`;
    if (!window.confirm(question)) return;
    onError(null);
    setLoading(true);
    const response = await fetch(`/api/platform/restaurants/${restaurant.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ isActive: next }),
    });
    setLoading(false);
    if (!response.ok) return onError(await readError(response, "Status wijzigen mislukt"));
    await onDone();
  }

  return (
    <li className="border border-neutral-200 rounded-lg p-3">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="font-medium">{restaurant.name}</div>
          <div className="text-sm text-neutral-500">
            {restaurant.userCount} {restaurant.userCount === 1 ? "gebruiker" : "gebruikers"}
          </div>
        </div>
        <span
          className={`text-xs px-2 py-1 rounded-full ${
            restaurant.isActive ? "bg-green-50 text-green-700" : "bg-amber-50 text-amber-700"
          }`}
        >
          {restaurant.isActive ? "Aan" : "Uit"}
        </span>
      </div>

      <div className="text-sm mt-2">
        {restaurant.owners.length === 0 ? (
          <span className="text-amber-700">Nog geen eigenaar</span>
        ) : (
          restaurant.owners.map((o, i) => (
            <div key={i} className="text-neutral-700">
              Eigenaar: {o.name}
              {o.email ? ` (${o.email})` : ""}
              {o.isActive ? "" : " — gedeactiveerd"}
            </div>
          ))
        )}
      </div>

      <div className="flex gap-2 mt-3">
        <button
          onClick={toggle}
          disabled={loading}
          className="flex-1 min-h-touch rounded-lg border border-neutral-300 text-sm disabled:opacity-50"
        >
          {loading ? "Bezig..." : restaurant.isActive ? "Zet uit" : "Zet aan"}
        </button>
        <button
          onClick={() => setShowInvite((v) => !v)}
          className="flex-1 min-h-touch rounded-lg border border-neutral-300 text-sm"
        >
          {showInvite ? "Annuleren" : "Eigenaar uitnodigen"}
        </button>
      </div>

      {showInvite && (
        <OwnerInviteForm
          restaurantId={restaurant.id}
          onDone={async () => {
            setShowInvite(false);
            await onDone();
          }}
          onError={onError}
        />
      )}
    </li>
  );
}

function OwnerInviteForm({
  restaurantId,
  onDone,
  onError,
}: {
  restaurantId: string;
  onDone: () => Promise<void>;
  onError: (m: string | null) => void;
}) {
  const [email, setEmail] = useState("");
  const [fullName, setFullName] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    onError(null);
    setLoading(true);
    const response = await fetch(`/api/platform/restaurants/${restaurantId}/owner`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, fullName }),
    });
    setLoading(false);
    if (!response.ok) return onError(await readError(response, "Uitnodigen mislukt"));
    await onDone();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3 bg-neutral-50 rounded-lg p-3 mt-3">
      <input
        value={fullName}
        onChange={(e) => setFullName(e.target.value)}
        placeholder="Naam eigenaar"
        required
        className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
      />
      <input
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder="E-mailadres eigenaar"
        required
        className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
      />
      <button
        type="submit"
        disabled={loading}
        className="w-full min-h-touch rounded-lg bg-neutral-900 text-white text-sm font-medium disabled:opacity-50"
      >
        {loading ? "Bezig..." : "Uitnodiging versturen"}
      </button>
    </form>
  );
}
