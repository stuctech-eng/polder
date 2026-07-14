export type UserRole = "owner" | "manager" | "administratie" | "bediening" | "keuken";

/**
 * Definitieve rechtenmatrix — single source of truth (klant-goedgekeurd, v1.31).
 * Rollen krijgen een set rechten; er wordt nooit op rolnaam gecodeerd (`if role === owner`),
 * altijd op permissie. Nieuwe rollen toevoegen = alleen hier een kolom uitbreiden.
 *
 * | Permissie                | Owner | Manager | Administratie | Bediening | Keuken |
 * |---------------------------|-------|---------|----------------|-----------|--------|
 * | VIEW_DASHBOARD            | ✅    | ✅      | ✅             | ❌        | ❌     |
 * | VIEW_REVENUE              | ✅    | ✅      | ✅             | ❌        | ❌     |
 * | MANAGE_COMPANIES          | ✅    | ❌      | ✅             | ❌        | ❌     |
 * | MANAGE_OPEN_TABS          | ✅    | ✅      | ✅             | ✅        | ❌     |
 * | MANAGE_RECEIPTS           | ✅    | ✅      | ✅             | ✅        | ❌     |
 * | APPROVE_RECEIPTS          | ✅    | ✅      | ❌             | ❌        | ❌     |
 * | MANAGE_INVOICES           | ✅    | ❌      | ✅             | ❌        | ❌     |
 * | VIEW_DAILY_CLOSING        | ✅    | ✅      | ✅             | ❌        | ❌     |
 * | EXECUTE_DAILY_CLOSING     | ✅    | ✅      | ❌             | ❌        | ❌     |
 * | MANAGE_TEAM               | ✅    | ❌      | ❌             | ❌        | ❌     |
 * | MANAGE_SETTINGS           | ✅    | ❌      | ✅             | ❌        | ❌     |
 */
export const PERMISSIONS = {
  VIEW_DASHBOARD: ["owner", "manager", "administratie"],
  VIEW_REVENUE: ["owner", "manager", "administratie"],
  MANAGE_COMPANIES: ["owner", "administratie"],
  MANAGE_OPEN_TABS: ["owner", "manager", "administratie", "bediening"],
  MANAGE_RECEIPTS: ["owner", "manager", "administratie", "bediening"],
  APPROVE_RECEIPTS: ["owner", "manager"],
  MANAGE_INVOICES: ["owner", "administratie"],
  VIEW_DAILY_CLOSING: ["owner", "manager", "administratie"],
  EXECUTE_DAILY_CLOSING: ["owner", "manager"],
  MANAGE_TEAM: ["owner"],
  MANAGE_SETTINGS: ["owner", "administratie"],
} as const;

export type Permission = keyof typeof PERMISSIONS;

export function roleHasPermission(role: UserRole, permission: Permission): boolean {
  return (PERMISSIONS[permission] as readonly string[]).includes(role);
}

export const ROLE_LABELS: Record<UserRole, string> = {
  owner: "Eigenaar",
  manager: "Manager",
  administratie: "Administratie",
  bediening: "Bediening",
  keuken: "Keuken",
};
