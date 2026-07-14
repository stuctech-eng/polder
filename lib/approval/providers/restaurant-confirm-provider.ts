import type { ApprovalProvider, ApprovalAttempt, ApprovalVerificationResult } from "../types";

/**
 * Eenvoudigste provider: geen PIN, geen geheime data. De ingelogde,
 * geautoriseerde gebruiker die op "Goedkeuren" klikt, IS de goedkeuring.
 * De eigenlijke autorisatie (mag deze gebruiker goedkeuren?) gebeurt al
 * vóór dit punt via requireRole("APPROVE_RECEIPTS") in de API-route.
 */
export const restaurantConfirmProvider: ApprovalProvider = {
  method: "restaurant_confirms",
  async verify(_attempt: ApprovalAttempt): Promise<ApprovalVerificationResult> {
    return { success: true };
  },
};
