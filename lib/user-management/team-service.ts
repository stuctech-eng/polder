import type { SupabaseClient } from "@supabase/supabase-js";
import * as userRepository from "./user-repository";
import * as userAdmin from "./user-admin-repository";
import { sendInvitation, removeAuthAccount } from "./invitation-service";
import { publishUserEvent } from "./events";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import type { UserRole } from "./role-helpers";
import type { AuthorizedContext } from "./permission-service";

/**
 * Generiek gebruikersbeheer — bewust niet "invite-service" genoemd (klant-instructie),
 * zodat resetPassword/resendInvitation/enable2FA/updateProfile er later zonder
 * architectuurwijziging bij kunnen.
 *
 * Security hardening stap 3 (H2): de gebruikersverbinding mag `users` alleen LEZEN. Alle schrijfacties lopen via
 * user-admin-repository (service-role). Elke functie hier wordt uitsluitend aangeroepen NA `requireRole("MANAGE_TEAM")`
 * (de ctx), controleert zelf expliciet dat het doelwit in HET RESTAURANT VAN DE AANROEPER zit (service-role kent geen RLS),
 * en de database bewaakt aanvullend de laatste actieve owner. Logging (activity_log, domain_events) blijft via de gebruikersverbinding.
 */

export async function listTeam(supabase: SupabaseClient, restaurantId: string) {
  return userRepository.listByRestaurant(supabase, restaurantId);
}

type InsertedProfile = Awaited<ReturnType<typeof userAdmin.insertProfile>>;

/**
 * Uitnodiging + profiel in één stap, gedeeld door teambeheer (inviteUser) en platformbeheer (eerste eigenaar).
 * Alleen aanroepen NA een autorisatiecheck (requireRole of requirePlatformAdmin); gebruikt de service-role.
 * Maakt het Auth-account aan, koppelt het profiel aan `restaurantId` en ruimt bij een fout een zojuist aangemaakt account op.
 * De uitnodigingsmail gaat vóór de profielaanmaak de deur uit; die kan geen transactie terugdraaien.
 */
export async function inviteProfile(
  params: { restaurantId: string; email: string; fullName: string; role: UserRole }
): Promise<InsertedProfile>;
export async function inviteProfile<T>(
  params: { restaurantId: string; email: string; fullName: string; role: UserRole },
  /** Eigen profielaanmaak (platformbeheer koppelt profiel + logregel in één databasetransactie). */
  createProfile: (authUserId: string) => Promise<T>
): Promise<T>;
export async function inviteProfile<T>(
  params: { restaurantId: string; email: string; fullName: string; role: UserRole },
  createProfile?: (authUserId: string) => Promise<T>
): Promise<T | InsertedProfile> {
  if (!userAdmin.isUserRole(params.role)) throw new Error("Ongeldige rol");
  const admin = createSupabaseAdminClient();

  const invite = await sendInvitation(params.email);
  const authUserId = invite.authUserId;

  // Een Auth-account dat al een profiel heeft (hier of in een ander restaurant) mag NOOIT worden overgenomen of opgeruimd.
  if (await userAdmin.profileExists(admin, authUserId)) {
    throw new Error("Dit e-mailadres is al in gebruik");
  }

  try {
    if (createProfile) return await createProfile(authUserId);
    return await userAdmin.insertProfile(admin, {
      id: authUserId,
      restaurantId: params.restaurantId,
      fullName: params.fullName,
      role: params.role,
    });
  } catch (err: any) {
    // Profielaanmaak mislukt: geen wees-Auth-account achterlaten (alleen als dit account zojuist door ons is aangemaakt).
    let cleanupNote = "";
    if (invite.isNewAccount) {
      const cleanup = await removeAuthAccount(authUserId);
      if (!cleanup.ok) {
        console.error("Uitnodiging: opruimen Auth-account mislukt", authUserId, cleanup.error);
        cleanupNote = " Het aangemaakte inlogaccount kon niet automatisch worden opgeruimd; neem contact op met de beheerder.";
      }
    }
    throw new Error(`Gebruiker kon niet worden aangemaakt: ${err?.message ?? "onbekende fout"}.${cleanupNote}`);
  }
}

export async function inviteUser(
  supabase: SupabaseClient,
  ctx: AuthorizedContext,
  params: { email: string; fullName: string; role: UserRole }
) {
  const newUser = await inviteProfile({ restaurantId: ctx.restaurantId, ...params });
  const authUserId = newUser.id;

  await publishUserEvent(supabase, {
    restaurantId: ctx.restaurantId,
    eventType: "UserInvited",
    payload: { invited_user_id: authUserId, role: params.role },
    publishedBy: ctx.userId,
  });

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `nodigde ${params.fullName} uit als ${params.role}`,
    target_table: "users",
    target_id: authUserId,
  });

  return newUser;
}

export async function updateRole(
  supabase: SupabaseClient,
  ctx: AuthorizedContext,
  targetUserId: string,
  newRole: UserRole
) {
  if (!userAdmin.isUserRole(newRole)) throw new Error("Ongeldige rol");
  const admin = createSupabaseAdminClient();

  const target = await userAdmin.findInRestaurant(admin, ctx.restaurantId, targetUserId);
  if (!target) throw new Error(userAdmin.NOT_FOUND_MESSAGE);

  // Guard: laatste actieve eigenaar van een restaurant mag niet gedegradeerd worden (de database bewaakt dit ook).
  if (target.role === "owner" && target.is_active && newRole !== "owner") {
    const ownerCount = await userAdmin.countActiveOwners(admin, ctx.restaurantId);
    if (ownerCount <= 1) {
      throw new Error("Kan de laatste eigenaar van dit restaurant niet degraderen");
    }
  }

  const updated = await userAdmin.updateRole(admin, ctx.restaurantId, targetUserId, newRole);

  await publishUserEvent(supabase, {
    restaurantId: ctx.restaurantId,
    eventType: "UserRoleChanged",
    payload: { target_user_id: targetUserId, old_role: target.role, new_role: newRole },
    publishedBy: ctx.userId,
  });

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `wijzigde rol van ${updated.full_name} naar ${newRole}`,
    target_table: "users",
    target_id: targetUserId,
  });

  return updated;
}

export async function setActive(
  supabase: SupabaseClient,
  ctx: AuthorizedContext,
  targetUserId: string,
  isActive: boolean
) {
  if (targetUserId === ctx.userId && !isActive) {
    throw new Error("Je kan jezelf niet deactiveren");
  }
  const admin = createSupabaseAdminClient();

  const target = await userAdmin.findInRestaurant(admin, ctx.restaurantId, targetUserId);
  if (!target) throw new Error(userAdmin.NOT_FOUND_MESSAGE);

  if (target.role === "owner" && target.is_active && !isActive) {
    const ownerCount = await userAdmin.countActiveOwners(admin, ctx.restaurantId);
    if (ownerCount <= 1) {
      throw new Error("Kan de laatste (actieve) eigenaar van dit restaurant niet deactiveren");
    }
  }

  const updated = await userAdmin.setActive(admin, ctx.restaurantId, targetUserId, isActive);

  await publishUserEvent(supabase, {
    restaurantId: ctx.restaurantId,
    eventType: isActive ? "UserActivated" : "UserDeactivated",
    payload: { target_user_id: targetUserId },
    publishedBy: ctx.userId,
  });

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `${isActive ? "activeerde" : "deactiveerde"} ${updated.full_name}`,
    target_table: "users",
    target_id: targetUserId,
  });

  return updated;
}

export async function removeUser(
  supabase: SupabaseClient,
  ctx: AuthorizedContext,
  targetUserId: string
): Promise<{ warning?: string }> {
  if (targetUserId === ctx.userId) {
    throw new Error("Je kan jezelf niet verwijderen");
  }
  const admin = createSupabaseAdminClient();

  const target = await userAdmin.findInRestaurant(admin, ctx.restaurantId, targetUserId);
  if (!target) throw new Error(userAdmin.NOT_FOUND_MESSAGE);

  if (target.role === "owner" && target.is_active) {
    const ownerCount = await userAdmin.countActiveOwners(admin, ctx.restaurantId);
    if (ownerCount <= 1) {
      throw new Error("Kan de laatste eigenaar van dit restaurant niet verwijderen");
    }
  }

  // FK-constraints (activity_log.user_id, audit_log.changed_by, bonnen, dagafsluitingen) voorkomen hard verwijderen van
  // gebruikers met historie — dat is gewenst; de repository vertaalt dit naar een begrijpelijke melding.
  await userAdmin.remove(admin, ctx.restaurantId, targetUserId);

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `verwijderde ${target.full_name}`,
    target_table: "users",
    target_id: targetUserId,
  });

  // Profiel en Auth-account blijven consistent: het inlogaccount van het verwijderde teamlid wordt ook opgeruimd.
  const cleanup = await removeAuthAccount(targetUserId);
  if (!cleanup.ok) {
    console.error("Teamlid verwijderd, maar Auth-account opruimen mislukt", targetUserId, cleanup.error);
    return { warning: "Het teamlid is verwijderd, maar het inlogaccount kon niet automatisch worden opgeruimd." };
  }
  return {};
}
