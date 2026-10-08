import { createSupabaseAdminClient } from "@/lib/supabase/admin";

export interface InviteResult {
  authUserId: string;
  emailSent: boolean;
  /** true = dit Auth-account is zojuist door deze uitnodiging aangemaakt (alleen dan mag het bij een fout worden opgeruimd) */
  isNewAccount: boolean;
  warning?: string;
}

// Een account geldt als "zojuist aangemaakt" als het minder dan 2 minuten oud is. Bewust ruim genoeg voor klokverschil,
// bewust conservatief: bij twijfel wordt een bestaand account NOOIT verwijderd.
const NEW_ACCOUNT_WINDOW_MS = 120_000;

/**
 * Nodigt een nieuwe medewerker uit via Supabase Auth's admin-API.
 * Maakt de auth-gebruiker aan; de aanroeper (team-service) koppelt daarna het profiel (restaurant_id, role)
 * server-side in de `users`-tabel en ruimt het Auth-account op als dat mislukt (geen wees-accounts).
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
    if (/already (been )?registered|already exists|email_exists/i.test(`${error.message} ${(error as any).code ?? ""}`)) {
      throw new Error("Dit e-mailadres is al in gebruik");
    }
    // Uitnodiging kan mislukken door de bekende mail-testlimiet — duidelijk melden (sectie 15: fouten zichtbaar).
    throw new Error(`Uitnodigingsmail kon niet verstuurd worden: ${error.message}`);
  }

  const createdAt = Date.parse(data.user.created_at);
  const isNewAccount = Number.isFinite(createdAt) && Date.now() - createdAt < NEW_ACCOUNT_WINDOW_MS;

  return { authUserId: data.user.id, emailSent: true, isNewAccount };
}

/**
 * Verwijdert een Auth-account (opruimen na een mislukte profielaanmaak, of na het verwijderen van een teamlid).
 * Eén herhaalpoging; gooit nooit — de aanroeper beslist wat er met `ok: false` gebeurt.
 */
export async function removeAuthAccount(authUserId: string): Promise<{ ok: boolean; error?: string }> {
  const admin = createSupabaseAdminClient();
  let lastError: string | undefined;
  for (let attempt = 0; attempt < 2; attempt++) {
    const { error } = await admin.auth.admin.deleteUser(authUserId);
    if (!error) return { ok: true };
    lastError = error.message;
  }
  return { ok: false, error: lastError };
}
