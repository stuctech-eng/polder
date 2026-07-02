"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

export default function ResetPasswordPage() {
  const router = useRouter();
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (password.length < 8) {
      setError("Wachtwoord moet minimaal 8 tekens zijn.");
      return;
    }
    if (password !== confirmPassword) {
      setError("Wachtwoorden komen niet overeen.");
      return;
    }

    setLoading(true);
    const supabase = createSupabaseBrowserClient();
    // De e-mail-link zet automatisch een tijdelijke sessie; updateUser
    // gebruikt die sessie om het wachtwoord te wijzigen.
    const { error: updateError } = await supabase.auth.updateUser({
      password,
    });
    setLoading(false);

    if (updateError) {
      setError(
        "Kon wachtwoord niet wijzigen. De link is mogelijk verlopen — vraag een nieuwe aan."
      );
      return;
    }

    router.push("/companies");
    router.refresh();
  }

  return (
    <main className="min-h-screen flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <h1 className="text-2xl font-semibold mb-1">Nieuw wachtwoord</h1>
        <p className="text-neutral-500 text-sm mb-8">
          Kies een nieuw wachtwoord voor je account.
        </p>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium mb-1" htmlFor="password">
              Nieuw wachtwoord
            </label>
            <input
              id="password"
              type="password"
              autoComplete="new-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full min-h-touch px-4 rounded-lg border border-neutral-300 bg-white"
            />
          </div>

          <div>
            <label className="block text-sm font-medium mb-1" htmlFor="confirmPassword">
              Bevestig wachtwoord
            </label>
            <input
              id="confirmPassword"
              type="password"
              autoComplete="new-password"
              required
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="w-full min-h-touch px-4 rounded-lg border border-neutral-300 bg-white"
            />
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
            {loading ? "Bezig..." : "Wachtwoord wijzigen"}
          </button>
        </form>
      </div>
    </main>
  );
}
