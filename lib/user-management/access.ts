/**
 * Toegangsstatus van de ingelogde gebruiker, bepaald door de database-functie public.my_access() (migratie 0025).
 * Alleen "ok" geeft toegang. Een fout of onbekende waarde wordt "onbekend" en geeft dus GEEN toegang (fail closed).
 * De database blijft de echte grens: bij een uitgezet restaurant of gedeactiveerde gebruiker geeft RLS niets terug.
 */
export type AccessStatus = "ok" | "niet_ingelogd" | "geen_profiel" | "gebruiker_uit" | "restaurant_uit" | "onbekend";

const KNOWN: readonly AccessStatus[] = ["ok", "niet_ingelogd", "geen_profiel", "gebruiker_uit", "restaurant_uit"];

export function parseAccess(data: unknown, error: unknown): AccessStatus {
  if (error) return "onbekend";
  return typeof data === "string" && (KNOWN as readonly string[]).includes(data) ? (data as AccessStatus) : "onbekend";
}

export function hasAccess(status: AccessStatus): boolean {
  return status === "ok";
}

/**
 * Navigatie (middleware): naar het inlogscherm met een melding als vaststaat dat de toegang dicht is.
 * null = niet doorsturen; bij "onbekend" of "geen_profiel" weigeren de pagina's zelf via requireRole.
 */
export function blockedReason(status: AccessStatus): "deactivated" | "restaurant_uit" | null {
  if (status === "gebruiker_uit") return "deactivated";
  if (status === "restaurant_uit") return "restaurant_uit";
  return null;
}

/** Melding voor de gebruiker; null = geen aparte melding nodig. */
export function accessMessage(status: AccessStatus): string | null {
  switch (status) {
    case "gebruiker_uit":
      return "Dit account is gedeactiveerd. Neem contact op met de eigenaar.";
    case "restaurant_uit":
      return "Dit restaurant staat uit. Neem contact op met de beheerder.";
    case "onbekend":
      return "Je toegang kon niet worden gecontroleerd. Probeer het opnieuw.";
    default:
      return null;
  }
}
