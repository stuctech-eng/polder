export type UserRole = "owner" | "manager" | "administratie" | "bediening" | "keuken";

/**
 * Permissie-matrix — centraal gedefinieerd, niet verspreid over de app.
 * Nieuwe permissies hier toevoegen, nooit losse role-checks in routes.
 */
export const PERMISSIONS = {
  MANAGE_TEAM: ["owner"],
  MANAGE_COMPANIES: ["owner", "administratie"],
  MANAGE_OPEN_TABS: ["owner", "manager", "bediening"],
  MANAGE_RECEIPTS: ["owner", "manager", "bediening"],
  APPROVE_RECEIPTS: ["owner", "manager"],
  MANAGE_INVOICES: ["owner", "administratie"],
  VIEW_REPORTS: ["owner", "administratie", "manager"],
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
