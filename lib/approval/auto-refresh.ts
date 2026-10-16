/**
 * Automatisch verversen van de rekeningpagina (16 okt 2026): alleen zolang er een bon wacht op goedkeuring via de
 * publieke link (QR of e-mail). Die goedkeuring gebeurt op een ander toestel, dus dit scherm merkt het anders niet.
 * PIN en restaurant_confirms gebeuren op dit scherm zelf en hebben geen verversen nodig.
 * Methode per bon: dezelfde keuze als het scherm (approval_method van de bon, anders de bedrijfsinstelling).
 */
export const AUTO_REFRESH_MS = 5000;

type Method = "pin" | "restaurant_confirms" | "email" | "qr" | null;

export interface AutoRefreshReceipt {
  status: string;
  approval_method?: Method;
  approval_conflict?: string | null;
}

export function needsAutoRefresh(
  receipts: AutoRefreshReceipt[],
  approvalEnabled: boolean,
  companyMethod: Method
): boolean {
  if (!approvalEnabled) return false;
  return receipts.some((r) => {
    if (r.status !== "pending_approval" || r.approval_conflict) return false;
    const method = r.approval_method !== undefined ? r.approval_method : companyMethod;
    return method === "qr" || method === "email";
  });
}
