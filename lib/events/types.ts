/**
 * Domain Events — stabiele contracten (governance-principe 6.1)
 *
 * Deze event-namen en payloads zijn onderdeel van de architectuur.
 * Wijzig ze niet los van een architectuurbeslissing (docs/architecture.md).
 * Modules publiceren events; andere modules (Notification, Audit & Activity,
 * Monitoring) abonneren zich zonder kennis van de bron-module.
 */

export type DomainEventType =
  | "TabOpened"
  | "TabClosed"
  | "ReceiptLinked"
  | "OcrCompleted"
  | "InvoiceRequested"
  | "InvoiceGenerated"
  | "PaymentReceived"
  | "ImportFailed"
  | "ImportCompleted"
  | "ConnectorError"
  | "UserInvited"
  | "UserRoleChanged"
  | "UserActivated"
  | "UserDeactivated";

export interface DomainEvent<TPayload = Record<string, unknown>> {
  restaurantId: string;
  eventType: DomainEventType;
  payload: TPayload;
  publishedBy?: string;
}
