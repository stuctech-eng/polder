import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { inviteProfile } from "@/lib/user-management/team-service";
import type { PlatformContext } from "./platform-access";

/**
 * Platformbeheer: restaurants aanmaken, aan/uit zetten, eerste eigenaar uitnodigen, logboek.
 * Gebruikt de service-role (de platformtabellen zijn alleen voor de server). Elke beheeractie loopt via een databasefunctie
 * (migratie 0027) die de actie EN de logregel in één transactie doet: mislukt de logregel, dan mislukt de actie ook. Elke functie hier wordt uitsluitend
 * aangeroepen NA requirePlatformAdmin(). Leest alleen platformgegevens (restaurant, status, gebruikers, eigenaar),
 * nooit restaurantinhoud (bonnen, facturen, omzet).
 */

export type PlatformAction = "restaurant_aangemaakt" | "restaurant_aan" | "restaurant_uit" | "eigenaar_uitgenodigd";

export interface PlatformRestaurant {
  id: string;
  name: string;
  isActive: boolean;
  createdAt: string;
  userCount: number;
  owners: { name: string; email: string | null; isActive: boolean }[];
}

export interface PlatformLogEntry {
  id: number;
  createdAt: string;
  action: PlatformAction;
  restaurantId: string | null;
  restaurantName: string | null;
  adminEmail: string | null;
  details: Record<string, unknown>;
}

export class PlatformError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}

/** Fout uit een actiefunctie (0027) vertalen: geen beheerder = 403, niet gevonden = 404, anders 500 met de melding. */
function actionError(error: { message: string; code?: string }, what: string) {
  if (error.code === "42501") return new PlatformError("Alleen voor platformbeheer", 403);
  if (error.code === "P0002") return new PlatformError("Restaurant niet gevonden", 404);
  return new PlatformError(`${what}: ${error.message}`, 500);
}

async function emailOf(userId: string): Promise<string | null> {
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.auth.admin.getUserById(userId);
  return error ? null : data.user?.email ?? null;
}

export async function listRestaurants(): Promise<PlatformRestaurant[]> {
  const admin = createSupabaseAdminClient();
  const { data: restaurants, error } = await admin
    .from("restaurants")
    .select("id, name, is_active, created_at")
    .order("name");
  if (error) throw new PlatformError(`Restaurants konden niet worden geladen: ${error.message}`, 500);

  const { data: users, error: usersError } = await admin
    .from("users")
    .select("id, restaurant_id, full_name, role, is_active");
  if (usersError) throw new PlatformError(`Gebruikers konden niet worden geladen: ${usersError.message}`, 500);

  const result: PlatformRestaurant[] = [];
  for (const r of restaurants ?? []) {
    const own = (users ?? []).filter((u) => u.restaurant_id === r.id);
    const owners = [];
    for (const o of own.filter((u) => u.role === "owner")) {
      owners.push({ name: o.full_name as string, email: await emailOf(o.id as string), isActive: o.is_active as boolean });
    }
    result.push({
      id: r.id as string,
      name: r.name as string,
      isActive: r.is_active as boolean,
      createdAt: r.created_at as string,
      userCount: own.length,
      owners,
    });
  }
  return result;
}

export async function createRestaurant(ctx: PlatformContext, name: string) {
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.rpc("platform_restaurant_aanmaken", { p_admin: ctx.adminUserId, p_naam: name });
  if (error) throw actionError(error, "Restaurant kon niet worden aangemaakt");
  return { id: data as string, name };
}

export async function setRestaurantActive(ctx: PlatformContext, restaurantId: string, active: boolean) {
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.rpc("platform_restaurant_status", {
    p_admin: ctx.adminUserId,
    p_restaurant: restaurantId,
    p_aan: active,
  });
  if (error) throw actionError(error, "Status kon niet worden gewijzigd");
  return { id: restaurantId, isActive: data as boolean };
}

export async function inviteOwner(ctx: PlatformContext, restaurantId: string, email: string, fullName: string) {
  const admin = createSupabaseAdminClient();
  // Vooraf controleren, zodat er voor een onbekend restaurant geen uitnodigingsmail de deur uit gaat.
  const { data: restaurant, error } = await admin.from("restaurants").select("id").eq("id", restaurantId).maybeSingle();
  if (error) throw new PlatformError(`Restaurant kon niet worden gecontroleerd: ${error.message}`, 500);
  if (!restaurant) throw new PlatformError("Restaurant niet gevonden", 404);

  try {
    const profile = await inviteProfile({ restaurantId, email, fullName, role: "owner" }, async (authUserId) => {
      const { error: linkError } = await admin.rpc("platform_eigenaar_koppelen", {
        p_admin: ctx.adminUserId,
        p_restaurant: restaurantId,
        p_user: authUserId,
        p_naam: fullName,
        p_email: email,
      });
      if (linkError) throw actionError(linkError, "Eigenaar kon niet worden gekoppeld");
      return { id: authUserId };
    });
    return { userId: profile.id };
  } catch (err: any) {
    throw err instanceof PlatformError ? err : new PlatformError(err?.message ?? "Uitnodigen mislukt", 400);
  }
}

export async function listLog(limit = 50): Promise<PlatformLogEntry[]> {
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin
    .from("platform_log")
    .select("id, created_at, action, restaurant_id, admin_user_id, details")
    .order("id", { ascending: false })
    .limit(limit);
  if (error) throw new PlatformError(`Logboek kon niet worden geladen: ${error.message}`, 500);

  const { data: restaurants } = await admin.from("restaurants").select("id, name");
  const names = new Map((restaurants ?? []).map((r) => [r.id as string, r.name as string]));
  const emails = new Map<string, string | null>();
  for (const id of new Set((data ?? []).map((l) => l.admin_user_id as string))) emails.set(id, await emailOf(id));

  return (data ?? []).map((l) => ({
    id: l.id as number,
    createdAt: l.created_at as string,
    action: l.action as PlatformAction,
    restaurantId: (l.restaurant_id as string | null) ?? null,
    restaurantName: l.restaurant_id ? names.get(l.restaurant_id as string) ?? null : null,
    adminEmail: emails.get(l.admin_user_id as string) ?? null,
    details: (l.details as Record<string, unknown>) ?? {},
  }));
}
