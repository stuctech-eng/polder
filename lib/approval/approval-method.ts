import type { ApprovalMethod } from "./types";

/**
 * Methode per bon (stap 14a, besluit 15 okt 2026) — DEZELFDE regel als de database (pin_eis, migratie 0038):
 *  - wachtende regel(s) van een soort: de methode en het bedrijf van die regel (vastgelegd bij het indienen);
 *  - geen wachtende regel: de huidige bedrijfsinstelling;
 *  - wachtende regels met verschillende methoden of bedrijven: weigeren, nooit zelf kiezen.
 * Gebruikt door de goedkeurroute en het scherm, zodat beide altijd hetzelfde besluiten.
 */
export interface ApprovalRule {
  method: string;
  company_id: string;
  status: string;
}

export type ReceiptApprovalMethod =
  | { ok: true; method: ApprovalMethod | null; companyId: string | null; fromRule: boolean }
  | { ok: false; reason: string };

export const CONFLICTING_RULES =
  "Deze bon heeft tegenstrijdige goedkeuringsregels en kan zo niet worden goedgekeurd. Neem contact op met een beheerder.";

/** Bon is goedgekeurd, maar een goedkeuringsregel staat nog op pending (bijwerken mislukte na de goedkeuring). */
export const ADMIN_INCOMPLETE_WARNING =
  "Goedgekeurd, maar de administratie is nog niet volledig bijgewerkt (goedkeuringsregel). Meld dit aan een beheerder.";

/** Waarschuwing uit de servergegevens: blijft staan zolang het probleem echt bestaat (ook na verversen of herladen). */
export function approvalWarningFor(status: string, rules: { status: string }[]): string | null {
  return (status === "approved" || status === "locked") && rules.some((r) => r.status === "pending")
    ? ADMIN_INCOMPLETE_WARNING
    : null;
}

export function methodForReceipt(
  rules: ApprovalRule[],
  tabCompanyId: string | null,
  companyMethod: ApprovalMethod | null
): ReceiptApprovalMethod {
  const pending = rules.filter((r) => r.status === "pending");
  if (pending.length === 0) {
    return { ok: true, method: companyMethod, companyId: tabCompanyId, fromRule: false };
  }
  const keys = new Set(pending.map((r) => `${r.method}|${r.company_id}`));
  if (keys.size > 1) {
    return { ok: false, reason: CONFLICTING_RULES };
  }
  return { ok: true, method: pending[0].method as ApprovalMethod, companyId: pending[0].company_id, fromRule: true };
}
