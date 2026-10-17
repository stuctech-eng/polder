/**
 * Modules per restaurant (fase 4, migraties 0028-0030). Stabiele sleutels; de database (tabel `features`) is de bron.
 * Deze lijst is alleen voor de UI (namen en volgorde). Een nieuwe module = een regel in het register via een migratie
 * plus een regel hier. De vaste kern (Bedrijven, Rekeningen en bonnen, Facturen, Team, Dashboard) is geen module.
 */
export const FEATURES = [
  { key: "daily_closing", label: "Dagafsluiting" },
  { key: "payment_registration", label: "Betalingen registreren" },
  { key: "approval", label: "Goedkeuring (PIN, QR, e-mail)" },
  // stap 14c (migratie 0043): standaard uit; werkt alleen samen met Goedkeuring
  { key: "signature", label: "Handtekening klant (bij Goedkeuring)" },
] as const;

export type FeatureKey = (typeof FEATURES)[number]["key"];

export const MODULE_OFF_MESSAGE = "Deze module staat uit voor dit restaurant.";

export function isFeatureKey(value: unknown): value is FeatureKey {
  return FEATURES.some((f) => f.key === value);
}
