/**
 * Mail-links (wachtwoord herstellen, uitnodiging) server-side controleren.
 *
 * Waarom: de browserclient gebruikt de PKCE-flow. Een herstel-link werkt dan alleen in exact de browser waarin hij is
 * aangevraagd (die bewaart de geheime sleutel). Op een iPhone opent Mail de link vaak elders (ander venster, privévenster,
 * in-app browser) en dan faalt het herstel. Met token_hash + verifyOtp controleert de server de link zelf: dat werkt in
 * elke browser en op elk toestel. De e-mailsjablonen in Supabase linken daarom naar /auth/confirm.
 */

export type EmailLinkType = "recovery" | "invite";

const TYPES: readonly EmailLinkType[] = ["recovery", "invite"];

export function parseEmailLinkType(value: string | null): EmailLinkType | null {
  return TYPES.includes(value as EmailLinkType) ? (value as EmailLinkType) : null;
}

/**
 * Alleen een pad binnen de eigen app (begint met één "/", geen "//" of "/\\"): geen open redirect naar een andere site.
 * Zonder geldig pad: herstel en uitnodiging gaan naar de pagina waar je een (nieuw) wachtwoord kiest.
 */
export function safeNextPath(next: string | null): string {
  if (next && /^\/(?![/\\])/.test(next)) return next;
  return "/reset-password";
}

/** Redenen die /reset-password begrijpt en als melding toont. */
export type LinkFailure = "ontbreekt" | "ongeldig";
