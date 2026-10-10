import { getCurrentUserContext } from "./session-context";
import { roleHasPermission, type Permission, type UserRole } from "./role-helpers";
import { accessMessage, hasAccess } from "./access";

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
 * Gebruikt de gecachte sessie-context (session-context.ts) — binnen één
 * pagina-render delen layout.tsx en de pagina zelf dezelfde query, i.p.v.
 * allebei apart "wie ben ik" te bevragen (prestatiefix, geen gedragswijziging).
 *
 * Gooit een PermissionError (met bruikbare status code) bij falen, zodat
 * API-routes die simpelweg kunnen doorgeven aan hun errorafhandeling.
 */
export async function requireRole(permission: Permission): Promise<AuthorizedContext> {
  const ctx = await getCurrentUserContext();

  if (!ctx) {
    throw new PermissionError("Niet ingelogd of geen restaurantprofiel gevonden", 401);
  }
  // Alleen my_access() = "ok" geeft toegang; elke andere uitkomst (ook een fout) weigert.
  if (!hasAccess(ctx.access)) {
    throw new PermissionError(accessMessage(ctx.access) ?? "Geen toegang", 403);
  }
  if (!roleHasPermission(ctx.role, permission)) {
    throw new PermissionError(
      `Deze actie vereist een rol met '${permission}'-rechten, jouw rol (${ctx.role}) heeft die niet`,
      403
    );
  }

  return { userId: ctx.userId, restaurantId: ctx.restaurantId, role: ctx.role };
}

export function hasPermission(role: UserRole, permission: Permission): boolean {
  return roleHasPermission(role, permission);
}
