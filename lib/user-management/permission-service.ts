import { createSupabaseServerClient } from "@/lib/supabase/server";
import { roleHasPermission, type Permission, type UserRole } from "./role-helpers";

export class PermissionError extends Error {
  status: number;
  constructor(message: string, status = 403) {
    super(message);
    this.status = status;
  }
}

export interface AuthorizedContext {
  userId: string;
  restaurantId: string;
  role: UserRole;
}

/**
 * Centrale autorisatiecheck — vanaf Fase A.5 verplicht voor alle nieuwe routes
 * (klant-instructie). Vervangt losse `if (user.role === "owner")`-checks.
 *
 * Gooit een PermissionError (met bruikbare status code) bij falen, zodat
 * API-routes die simpelweg kunnen doorgeven aan hun errorafhandeling.
 */
export async function requireRole(permission: Permission): Promise<AuthorizedContext> {
  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    throw new PermissionError("Niet ingelogd", 401);
  }

  const { data: profile } = await supabase
    .from("users")
    .select("restaurant_id, role, is_active")
    .eq("id", userData.user.id)
    .single();

  if (!profile) {
    throw new PermissionError("Geen restaurantprofiel gevonden", 400);
  }
  if (profile.is_active === false) {
    throw new PermissionError("Account is gedeactiveerd", 403);
  }

  const role = profile.role as UserRole;
  if (!roleHasPermission(role, permission)) {
    throw new PermissionError(
      `Deze actie vereist een rol met '${permission}'-rechten, jouw rol (${role}) heeft die niet`,
      403
    );
  }

  return { userId: userData.user.id, restaurantId: profile.restaurant_id, role };
}

export function hasPermission(role: UserRole, permission: Permission): boolean {
  return roleHasPermission(role, permission);
}
