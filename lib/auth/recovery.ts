import { createClient } from "@supabase/supabase-js";

/**
 * Herstelmail aanvragen VANAF DE SERVER, met de implicit flow.
 *
 * Waarom: vroeg de browser de mail aan (PKCE), dan werkte de link alleen in precies die browser. Op een iPhone opent Mail
 * de link vaak in een ander venster en dan faalde het herstel. Met de implicit flow staat de sessie in de link zelf
 * (#access_token=…); /reset-password leest die uit. Zo werkt de standaard Supabase-mail zonder aangepast sjabloon,
 * in elke browser en op elk toestel. Gebruikt de publieke (anon) sleutel, niet de service-sleutel.
 */
export function siteUrl(): string {
  return process.env.NEXT_PUBLIC_SITE_URL || "https://polder.vercel.app";
}

export async function requestPasswordReset(email: string): Promise<{ error: string | null }> {
  const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    auth: { flowType: "implicit", persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: `${siteUrl()}/reset-password` });
  return { error: error ? error.message : null };
}
