import { cache } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PermissionError } from "@/lib/user-management/permission-service";
import { MODULE_OFF_MESSAGE, type FeatureKey } from "./features";

/**
 * Staat een module aan voor het restaurant van de ingelogde gebruiker? Via public.my_feature() (SECURITY DEFINER,
 * restaurant bepaald door de database). Fail closed: alleen een expliciet `true` zonder fout telt; een fout, `null`,
 * iets anders of een ontbrekende functie = uit.
 */
export const isFeatureOn = cache(async (key: FeatureKey): Promise<boolean> => {
  const supabase = createSupabaseServerClient();
  const { data, error } = await supabase.rpc("my_feature", { p_key: key });
  return !error && data === true;
});

/**
 * Verplicht in elke route/pagina van een module, ALTIJD NA requireRole() en nooit in plaats daarvan.
 * Geeft geen enkel extra recht; weigert met 403 als de module uit staat (of de controle faalt).
 * De databasewacht (0030) blokkeert dezelfde schrijfacties ook als een route deze controle zou vergeten.
 */
export async function requireFeature(key: FeatureKey): Promise<void> {
  if (!(await isFeatureOn(key))) throw new PermissionError(MODULE_OFF_MESSAGE, 403);
}

/**
 * Voor routes zonder ingelogde gebruiker (publieke goedkeuringslink, service-sleutel): controle op het restaurant van
 * de rij zelf via public.feature_aan(). Fail closed.
 */
export async function isFeatureOnForRestaurant(
  admin: SupabaseClient,
  restaurantId: string | null | undefined,
  key: FeatureKey
): Promise<boolean> {
  if (!restaurantId) return false;
  const { data, error } = await admin.rpc("feature_aan", { p_restaurant: restaurantId, p_key: key });
  return !error && data === true;
}
