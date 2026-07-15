export interface EmailMessage {
  to: string;
  subject: string;
  html: string;
  replyTo?: string;
}

export interface EmailSendResult {
  success: boolean;
  error?: string;
}

/**
 * Email Provider Interface (governance 6.4). De Notification/Approval-code
 * kent uitsluitend deze interface, nooit een concrete provider rechtstreeks.
 * Resend is de standaardimplementatie; een andere provider (SMTP, Microsoft
 * 365) toevoegen betekent alleen een nieuwe implementatie van dit contract.
 */
export interface EmailProvider {
  send(message: EmailMessage): Promise<EmailSendResult>;
}
