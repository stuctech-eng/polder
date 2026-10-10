import { cache } from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PermissionError } from "@/lib/user-management/permission-service";

/**
 * Platformbeheer (migratie 0026). Een platformbeheerder staat in public.platform_admins (alleen met SQL te vullen)
 * en heeft GEEN restaurantprofiel: hij ziet platformgegevens, nooit restaurantinhoud.
 *
 * Fail closed: alleen een expliciet `true` van is_platform_admin() telt; een fout of iets anders = geen beheerder.
 */
export const isPlatformAdmin = cache(async (): Promise<boolean> => {
  const supabase = createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return false;

  const { data, error } = await supabase.rpc("is_platform_admin");
  return !error && data === true;
});

export interface PlatformContext {
  adminUserId: string;
}

/** Verplicht vóór elke platformactie (routes en pagina's). Gooit PermissionError (401/403). */
export async function requirePlatformAdmin(): Promise<PlatformContext> {
  const supabase = createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new PermissionError("Niet ingelogd", 401);

  if (!(await isPlatformAdmin())) {
    throw new PermissionError("Alleen voor platformbeheer", 403);
  }
  return { adminUserId: user.id };
}
