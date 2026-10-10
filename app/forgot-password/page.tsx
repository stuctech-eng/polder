"use client";

import { useState } from "react";
import Link from "next/link";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "sent" | "error">("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setStatus("idle");
    setErrorMessage(null);

    // De server vraagt de mail aan (lib/auth/recovery.ts): dan werkt de link in elke browser en elk venster.
    const response = await fetch("/api/auth/forgot-password", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    }).catch(() => null);

    setLoading(false);
    if (response?.ok) {
      setStatus("sent");
      return;
    }
    const body = response ? await response.json().catch(() => ({})) : {};
    setErrorMessage(body.error ?? "Geen verbinding met de server.");
    setStatus("error");
  }

  return (
    <main className="min-h-screen flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <h1 className="text-2xl font-semibold mb-1">Wachtwoord vergeten</h1>
        <p className="text-neutral-500 text-sm mb-8">
          Vul je e-mailadres in, dan sturen we een resetlink.
        </p>

        {status === "sent" ? (
          <p className="text-sm text-green-700 bg-green-50 border border-green-200 rounded-lg p-4">
            Check je e-mail (ook de spam-map) voor de resetlink. Deze is
            beperkt geldig.
          </p>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium mb-1" htmlFor="email">
                E-mailadres
              </label>
              <input
                id="email"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full min-h-touch px-4 rounded-lg border border-neutral-300 bg-white"
              />
            </div>

            {status === "error" && (
              <p className="text-sm text-red-600" role="alert">
                Er ging iets mis. {errorMessage}
              </p>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full min-h-touch rounded-lg bg-neutral-900 text-white font-medium disabled:opacity-50"
            >
              {loading ? "Bezig..." : "Verstuur resetlink"}
            </button>
          </form>
        )}

        <Link
          href="/login"
          className="block mt-6 text-sm text-neutral-500 text-center"
        >
          Terug naar inloggen
        </Link>
      </div>
    </main>
  );
}
