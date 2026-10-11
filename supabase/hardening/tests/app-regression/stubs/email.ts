// Nep-mailer voor app-tests: telt verzonden mails in globalThis.__mails (er gaat niets de deur uit).
export async function sendEmail(message: { to: string; subject: string; html: string }) {
  const g = globalThis as any;
  g.__mails = (g.__mails ?? []).concat([message]);
  return { success: true };
}
