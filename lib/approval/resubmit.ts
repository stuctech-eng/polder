/**
 * Opnieuw indienen van een afgewezen bon (plan 7b): de aanroep van de bestaande route
 * `POST /api/receipts/[id]/request-approval`, los van React zodat succes én mislukking
 * (serverfout, onleesbaar antwoord, netwerkfout) testbaar zijn. Geeft nooit een exception terug.
 */

export type ResubmitResult =
  | { ok: true; approvalToken: string | null; approvalWarning: string | null }
  | { ok: false; error: string };

/**
 * Uitleg bij een mislukte poging: wat is er aan de hand en wat kan de gebruiker doen.
 * De melding van de server blijft herkenbaar als reden bewaard.
 */
export function resubmitErrorMessage(serverError?: string): string {
  const e = serverError ?? "";
  if (/niet ingeschakeld/i.test(e)) {
    return "Goedkeuring staat voor dit bedrijf uit, dus de bon kan niet opnieuw worden ingediend. Laat een beheerder goedkeuring weer inschakelen, of verwijder deze bon.";
  }
  if (/geen gekoppeld bedrijf/i.test(e)) {
    return "Deze rekening heeft geen bedrijf, dus er kan geen goedkeuring worden aangevraagd. Koppel een bedrijf, of verwijder deze bon.";
  }
  if (/pending_approval/.test(e)) {
    return "Deze bon wacht al op goedkeuring.";
  }
  if (/status '(approved|locked)'/.test(e)) {
    return "Deze bon is al afgehandeld en hoeft niet opnieuw ingediend te worden.";
  }
  return `${e || "Opnieuw indienen is mislukt."} Probeer het opnieuw of neem contact op met een beheerder.`;
}

export async function requestResubmit(
  fetchImpl: (input: string, init?: { method: string }) => Promise<{ ok: boolean; json: () => Promise<any> }>,
  receiptId: string
): Promise<ResubmitResult> {
  try {
    const response = await fetchImpl(`/api/receipts/${receiptId}/request-approval`, { method: "POST" });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      return { ok: false, error: resubmitErrorMessage(body?.error) };
    }
    return { ok: true, approvalToken: body?.approvalToken ?? null, approvalWarning: body?.approvalWarning ?? null };
  } catch {
    return {
      ok: false,
      error: "Geen verbinding met de server — de bon is niet opnieuw ingediend. Controleer je verbinding en probeer het opnieuw.",
    };
  }
}
