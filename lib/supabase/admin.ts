import { createClient } from "@supabase/supabase-js";

/**
 * Service-role client — omzeilt RLS volledig.
 *
 * ALLEEN gebruiken in server-side code (API routes, Server Components) voor
 * acties die de normale gebruikersrechten bewust moeten overstijgen, zoals
 * het aanmaken van een Supabase Auth-gebruiker bij het uitnodigen van
 * teamleden. NOOIT importeren in een Client Component ("use client") — de
 * service_role key mag nooit naar de browser lekken.
 */
export function createSupabaseAdminClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );
}
