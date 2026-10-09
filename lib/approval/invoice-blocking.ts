/**
 * Facturatieblokkade voor bonnen (plan 7b, zie docs/architecture.md).
 *
 * Twee afzonderlijke oordelen, bewust gescheiden:
 *
 * 1. Afwijzingsblokkade — een bon is geblokkeerd als
 *      - minstens één goedkeuring de status 'rejected' heeft, én
 *      - geen enkele goedkeuring de status 'approved' heeft, én
 *      - de bonstatus niet 'approved' of 'locked' is.
 *    Dezelfde definitie staat in de database (migratie 0023, open_tabs_guard) voor de
 *    overgang closed -> invoiced. Een test bewijst dat app en database gelijk oordelen.
 *    Een regel met alleen 'expired' blokkeert niet.
 *
 * 2. Facturatieblokkade — mag de bon nu in een factuur? Afwijzingsblokkade OF de bon
 *    wacht op goedkeuring (status 'pending_approval'). Dat laatste staat alleen in de app.
 *
 * Geen databasetoegang en geen bijwerkingen: pure functies, los te testen.
 */

export type ReceiptLike = { status: string };
export type ApprovalLike = { status: string };

export type InvoiceBlockReason = "pending" | "rejected";

/** Afwijzingsblokkade: afgewezen en nog niet opnieuw goedgekeurd. */
export function isRejectionBlocked(receipt: ReceiptLike, approvals: ApprovalLike[]): boolean {
  if (receipt.status === "approved" || receipt.status === "locked") return false;
  const hasRejected = approvals.some((a) => a.status === "rejected");
  const hasApproved = approvals.some((a) => a.status === "approved");
  return hasRejected && !hasApproved;
}

/** Facturatieblokkade: afwijzingsblokkade of bon in wacht op goedkeuring. */
export function isInvoiceBlocked(receipt: ReceiptLike, approvals: ApprovalLike[]): boolean {
  return invoiceBlockReason(receipt, approvals) !== null;
}

/**
 * Reden van de facturatieblokkade. 'pending' gaat voor 'rejected': een opnieuw ingediende bon
 * krijgt de bestaande melding "wacht nog op goedkeuring".
 */
export function invoiceBlockReason(receipt: ReceiptLike, approvals: ApprovalLike[]): InvoiceBlockReason | null {
  if (receipt.status === "pending_approval") return "pending";
  if (isRejectionBlocked(receipt, approvals)) return "rejected";
  return null;
}
