import type { SupabaseClient } from "@supabase/supabase-js";
import type { UserRole } from "./role-helpers";

/**
 * ENIGE plek waar de `users`-tabel geschreven wordt (security hardening stap 3, H2).
 *
 * De gebruikersverbinding heeft GEEN schrijfrechten meer op `users` (INSERT/UPDATE/DELETE ingetrokken, migratie 0017).
 * Schrijven gebeurt hier met de service-role client (omzeilt RLS) en daarom:
 *  - elke functie krijgt het restaurant van de AANROEPER (uit requireRole) en scoped elke query daarop;
 *  - de aanroeper (team-service) heeft vooraf `requireRole("MANAGE_TEAM")` gedaan;
 *  - de database bewaakt aanvullend: id/restaurant_id onveranderlijk en minstens één actieve owner (ook voor service-role).
 * Nooit importeren in een Client Component.
 */

export const USER_ROLES: readonly UserRole[] = ["owner", "manager", "administratie", "bediening", "keuken"];

export function isUserRole(value: unknown): value is UserRole {
  return typeof value === "string" && (USER_ROLES as readonly string[]).includes(value);
}

export const NOT_FOUND_MESSAGE = "Gebruiker niet gevonden in dit restaurant";
export const LAST_OWNER_MESSAGE = "Een restaurant moet minstens één actieve eigenaar houden";

/** Vertaalt bekende databasefouten naar begrijpelijke meldingen; andere fouten blijven ongewijzigd. */
function mapDbError(err: any, when?: "remove"): Error {
  if (/actieve eigenaar/i.test(err?.message ?? "")) return new Error(LAST_OWNER_MESSAGE);
  if (err?.code === "23503" && when === "remove") {
    return new Error(
      "Deze gebruiker heeft al historie (bonnen/facturen/activiteit) en kan niet " +
        "verwijderd worden — deactiveer het account in plaats daarvan"
    );
  }
  if (err?.code === "23505") {
    return new Error("Dit e-mailadres is al in gebruik");
  }
  return err instanceof Error ? err : new Error(err?.message ?? "Onbekende databasefout");
}

const COLUMNS = "id, restaurant_id, full_name, role, is_active, two_factor_enabled, created_at, updated_at";

/** Profiel opzoeken BINNEN het restaurant van de aanroeper; null als het er niet (in dit restaurant) is. */
export async function findInRestaurant(admin: SupabaseClient, restaurantId: string, userId: string) {
  const { data, error } = await admin
    .from("users")
    .select(COLUMNS)
    .eq("id", userId)
    .eq("restaurant_id", restaurantId)
    .maybeSingle();
  if (error) throw mapDbError(error);
  return data;
}

/** Bestaat er al een profiel (in welk restaurant dan ook) voor dit auth-account? */
export async function profileExists(admin: SupabaseClient, userId: string): Promise<boolean> {
  const { data, error } = await admin.from("users").select("id").eq("id", userId).maybeSingle();
  if (error) throw mapDbError(error);
  return !!data;
}

export async function countActiveOwners(admin: SupabaseClient, restaurantId: string): Promise<number> {
  const { count, error } = await admin
    .from("users")
    .select("id", { count: "exact", head: true })
    .eq("restaurant_id", restaurantId)
    .eq("role", "owner")
    .eq("is_active", true);
  if (error) throw mapDbError(error);
  return count ?? 0;
}

export async function insertProfile(
  admin: SupabaseClient,
  params: { id: string; restaurantId: string; fullName: string; role: UserRole }
) {
  if (!isUserRole(params.role)) throw new Error("Ongeldige rol");
  const { data, error } = await admin
    .from("users")
    .insert({ id: params.id, restaurant_id: params.restaurantId, full_name: params.fullName, role: params.role })
    .select(COLUMNS)
    .single();
  if (error) throw mapDbError(error);
  return data;
}

export async function updateRole(admin: SupabaseClient, restaurantId: string, userId: string, role: UserRole) {
  if (!isUserRole(role)) throw new Error("Ongeldige rol");
  const { data, error } = await admin
    .from("users")
    .update({ role, updated_at: new Date().toISOString() })
    .eq("id", userId)
    .eq("restaurant_id", restaurantId)
    .select(COLUMNS)
    .maybeSingle();
  if (error) throw mapDbError(error);
  if (!data) throw new Error(NOT_FOUND_MESSAGE);
  return data;
}

export async function setActive(admin: SupabaseClient, restaurantId: string, userId: string, isActive: boolean) {
  const { data, error } = await admin
    .from("users")
    .update({ is_active: isActive, updated_at: new Date().toISOString() })
    .eq("id", userId)
    .eq("restaurant_id", restaurantId)
    .select(COLUMNS)
    .maybeSingle();
  if (error) throw mapDbError(error);
  if (!data) throw new Error(NOT_FOUND_MESSAGE);
  return data;
}

export async function remove(admin: SupabaseClient, restaurantId: string, userId: string) {
  const { data, error } = await admin
    .from("users")
    .delete()
    .eq("id", userId)
    .eq("restaurant_id", restaurantId)
    .select("id");
  if (error) throw mapDbError(error, "remove");
  if (!data || data.length === 0) throw new Error(NOT_FOUND_MESSAGE);
}
