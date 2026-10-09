import { roleHasPermission } from "@/lib/user-management/role-helpers";
export class PermissionError extends Error { status: number; constructor(m: string, s = 403) { super(m); this.status = s; } }
export async function requireRole(p: any) {
  const c = (globalThis as any).__cur;
  if (!c) throw new PermissionError("Niet ingelogd", 401);
  if (!roleHasPermission(c.role, p)) throw new PermissionError(`rol ${c.role} mist ${p}`, 403);
  return { userId: c.id, restaurantId: c.restaurantId, role: c.role };
}
export function hasPermission(role: any, p: any) { return roleHasPermission(role, p); }
