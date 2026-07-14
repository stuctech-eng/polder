export type ApprovalMethod = "pin" | "restaurant_confirms" | "email" | "qr" | "signature";

export interface ApprovalAttempt {
  /** Providerspecifieke input — voor PIN de ingevoerde code, voor
   * restaurant_confirms leeg (de actie zelf is de bevestiging). */
  credential?: string;
  approverName: string;
}

export interface ApprovalVerificationResult {
  success: boolean;
  reason?: string;
}

/**
 * Approval Provider Interface (governance 6.4-patroon, nu toegepast op
 * goedkeuring i.p.v. e-mail). De Approval Service kent uitsluitend deze
 * interface — nooit een concrete provider-implementatie rechtstreeks.
 * Nieuwe providers (Email/QR/Signature, Fase C/D) hoeven alleen dit
 * contract te implementeren, geen wijziging aan de Service of Receipt
 * Manager.
 */
export interface ApprovalProvider {
  method: ApprovalMethod;
  verify(
    attempt: ApprovalAttempt,
    settings: { pinHash?: string | null; pinSalt?: string | null }
  ): Promise<ApprovalVerificationResult>;
}
