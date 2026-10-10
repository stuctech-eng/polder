import { cache } from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { UserRole } from "./role-helpers";
import { parseAccess, type AccessStatus } from "./access";

export interface CurrentUserContext {
  userId: string;
  restaurantId: string;
  role: UserRole;
  /** Toegang volgens public.my_access(): alleen "ok" geeft toegang (gebruiker én restaurant actief). */
  access: AccessStatus;
  /** true alleen als access === "ok" (gebruiker actief én restaurant aan). */
  isActive: boolean;
}

/**
 * React's cache() dedupliceert aanroepen met dezelfde argumenten binnen één
 * enkele server-request/render-pass. Zonder dit deed layout.tsx (voor de
 * navigatiebalk) en elke pagina (via requireRole) allebei apart dezelfde
 * "wie ben ik, welke rol" query — nu gebeurt dat maar één keer per
 * paginabezoek, gedeeld tussen alle server components in die render.
 */
export const getCurrentUserContext = cache(async (): Promise<CurrentUserContext | null> => {
  const supabase = createSupabaseServerClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data: profile } = await supabase
    .from("users")
    .select("restaurant_id, role")
    .eq("id", user.id)
    .single();

  if (!profile) return null;

  // Gebruiker én restaurant actief? Een fout of onbekende waarde = geen toegang (fail closed).
  const { data, error } = await supabase.rpc("my_access");
  const access = parseAccess(data, error);

  return {
    userId: user.id,
    restaurantId: profile.restaurant_id,
    role: profile.role as UserRole,
    access,
    isActive: access === "ok",
  };
});
