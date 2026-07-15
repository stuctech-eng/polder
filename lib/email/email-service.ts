import type { EmailMessage, EmailSendResult } from "./types";
import { resendProvider } from "./providers/resend-provider";

/**
 * Enige aanspreekpunt voor e-mail versturen in de hele app — geen enkele
 * aanroeper importeert resendProvider rechtstreeks (governance 6.4).
 */
export async function sendEmail(message: EmailMessage): Promise<EmailSendResult> {
  return resendProvider.send(message);
}
