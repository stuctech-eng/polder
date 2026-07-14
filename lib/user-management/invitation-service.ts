import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import type { UserRole } from "./role-helpers";

export interface InviteResult {
  authUserId: string;
  emailSent: boolean;
  warning?: string;
}

/**
 * Nodigt een nieuwe medewerker uit via Supabase Auth's admin-API.
 * Maakt de auth-gebruiker aan; de aanroeper (team-service) koppelt daarna
 * het profiel (restaurant_id, role) in de publieke `users`-tabel.
 *
 * Let op: valt onder dezelfde Resend-testlimiet als wachtwoord-reset (v1.3) —
 * totdat een eigen domein geverifieerd is, komt de uitnodigingsmail alleen aan
 * bij het Resend-testaccountadres.
 */
export async function sendInvitation(email: string): Promise<InviteResult> {
  const admin = createSupabaseAdminClient();

  // Zonder expliciete redirectTo zou de uitnodigingslink iemand direct kunnen
  // inloggen via een tijdelijke sessie, zonder ooit een eigen wachtwoord te
  // kiezen — dat zou hen bij een volgend bezoek buitensluiten. Door naar
  // /reset-password te wijzen (dezelfde pagina als wachtwoord-vergeten)
  // kiest de nieuwe medewerker altijd expliciet een eigen wachtwoord.
  const redirectTo = `${process.env.NEXT_PUBLIC_SITE_URL || "https://polder.vercel.app"}/reset-password`;

  const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo });

  if (error) {
    // Uitnodiging kan mislukken door de bekende mail-testlimiet — dat is geen
    // reden om de hele flow te blokkeren, wel om duidelijk te waarschuwen
    // (sectie 15: fouten zichtbaar, actie niet onnodig laten falen).
    throw new Error(`Uitnodigingsmail kon niet verstuurd worden: ${error.message}`);
  }

  return { authUserId: data.user.id, emailSent: true };
}
