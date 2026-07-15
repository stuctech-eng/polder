import { cache } from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { UserRole } from "./role-helpers";

export interface CurrentUserContext {
  userId: string;
  restaurantId: string;
  role: UserRole;
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
    .select("restaurant_id, role, is_active")
    .eq("id", user.id)
    .single();

  if (!profile) return null;

  return {
    userId: user.id,
    restaurantId: profile.restaurant_id,
    role: profile.role as UserRole,
    isActive: profile.is_active !== false,
  };
});
