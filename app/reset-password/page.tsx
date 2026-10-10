"use client";

import { useEffect, useState, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";
import { parseHashSession } from "@/lib/auth/email-link";

const LINK_MESSAGES: Record<string, string> = {
  ontbreekt: "Deze link is onvolledig. Vraag hieronder een nieuwe link aan.",
  ongeldig: "Deze link is ongeldig of verlopen (een link werkt maar één keer). Vraag hieronder een nieuwe link aan.",
};

type SessionState = "checking" | "ok" | "missing";

function ResetPasswordForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const linkProblem = searchParams.get("link");
  const linkDetail = searchParams.get("detail");

  const [session, setSession] = useState<SessionState>("checking");
  const [sessionError, setSessionError] = useState<string | null>(null);
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // Vooraf controleren of de mail-link een (tijdelijke) sessie heeft gezet, zodat een ongeldige link
  // meteen zichtbaar is in plaats van pas na het invullen van het formulier.
  useEffect(() => {
    if (linkProblem) {
      setSession("missing");
      return;
    }
    const supabase = createSupabaseBrowserClient();
    (async () => {
      // Herstel-link (aangevraagd door de server) of uitnodiging: de sessie staat in het #-deel van de link.
      const fromHash = parseHashSession(window.location.hash);
      if (fromHash) {
        window.history.replaceState(null, "", window.location.pathname + window.location.search);
        if ("error" in fromHash) {
          setSession("missing");
          setSessionError(fromHash.error);
          return;
        }
        const { error: sessionSetError } = await supabase.auth.setSession({
          access_token: fromHash.accessToken,
          refresh_token: fromHash.refreshToken,
        });
        if (sessionSetError) {
          setSession("missing");
          setSessionError(sessionSetError.message);
          return;
        }
      }
      const { data, error: userError } = await supabase.auth.getUser();
      if (data.user) {
        setSession("ok");
      } else {
        setSession("missing");
        setSessionError(userError?.message ?? null);
      }
    })();
  }, [linkProblem]);

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
    const { error: updateError } = await supabase.auth.updateUser({ password });
    setLoading(false);

    if (updateError) {
      // Fouten zichtbaar in de UI (sectie 15), inclusief de technische melding.
      setError(`Kon wachtwoord niet wijzigen: ${updateError.message}`);
      return;
    }

    // De startpagina stuurt iedereen naar de juiste plek (restaurant of platformbeheer).
    router.push("/");
    router.refresh();
  }

  return (
    <main className="min-h-screen flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <h1 className="text-2xl font-semibold mb-1">Nieuw wachtwoord</h1>
        <p className="text-neutral-500 text-sm mb-8">Kies een nieuw wachtwoord voor je account.</p>

        {session === "checking" && <p className="text-sm text-neutral-500">Link controleren...</p>}

        {session === "missing" && (
          <div className="space-y-4">
            <div className="text-sm text-amber-700 bg-amber-50 border border-amber-200 rounded-lg p-3" role="alert">
              <p>{LINK_MESSAGES[linkProblem ?? ""] ?? "Er is geen geldige link gebruikt. Vraag hieronder een nieuwe link aan."}</p>
              {(linkDetail || sessionError) && (
                <p className="mt-2 text-xs text-amber-800">Technische melding: {linkDetail ?? sessionError}</p>
              )}
            </div>
            <a
              href="/forgot-password"
              className="w-full min-h-touch rounded-lg bg-neutral-900 text-white font-medium flex items-center justify-center"
            >
              Nieuwe link aanvragen
            </a>
          </div>
        )}

        {session === "ok" && (
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
        )}
      </div>
    </main>
  );
}

export default function ResetPasswordPage() {
  return (
    <Suspense fallback={null}>
      <ResetPasswordForm />
    </Suspense>
  );
}
