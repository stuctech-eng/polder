import type { EmailProvider, EmailMessage, EmailSendResult } from "../types";

/**
 * Standaardimplementatie van de Email Provider Interface. Gebruikt plain
 * fetch naar de Resend API — geen extra npm-dependency nodig (zelfde
 * afweging als bij pdf-lib: minimaal, geen onnodige toevoegingen).
 *
 * Let op: dit is een aparte, eigen API key (RESEND_API_KEY) van de SMTP-
 * configuratie die Supabase Auth gebruikt voor wachtwoord-reset/uitnodigen
 * — die twee delen geen credentials, ook al is het dezelfde Resend-account.
 */
export const resendProvider: EmailProvider = {
  async send(message: EmailMessage): Promise<EmailSendResult> {
    const apiKey = process.env.RESEND_API_KEY;
    if (!apiKey) {
      return { success: false, error: "RESEND_API_KEY ontbreekt in de environment variables" };
    }

    const fromAddress = process.env.RESEND_FROM_ADDRESS || "Polder <onboarding@resend.dev>";

    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: fromAddress,
          to: [message.to],
          subject: message.subject,
          html: message.html,
          reply_to: message.replyTo,
        }),
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        return { success: false, error: body?.message || `Resend-fout (${response.status})` };
      }

      return { success: true };
    } catch (err: any) {
      return { success: false, error: err?.message || "Onbekende netwerkfout bij versturen" };
    }
  },
};
