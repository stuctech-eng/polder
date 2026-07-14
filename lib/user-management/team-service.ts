import type { SupabaseClient } from "@supabase/supabase-js";
import * as userRepository from "./user-repository";
import { sendInvitation } from "./invitation-service";
import { publishUserEvent } from "./events";
import type { UserRole } from "./role-helpers";
import type { AuthorizedContext } from "./permission-service";

/**
 * Generiek gebruikersbeheer — bewust niet "invite-service" genoemd (klant-instructie),
 * zodat resetPassword/resendInvitation/enable2FA/updateProfile er later zonder
 * architectuurwijziging bij kunnen.
 */

export async function listTeam(supabase: SupabaseClient, restaurantId: string) {
  return userRepository.listByRestaurant(supabase, restaurantId);
}

export async function inviteUser(
  supabase: SupabaseClient,
  ctx: AuthorizedContext,
  params: { email: string; fullName: string; role: UserRole }
) {
  const { authUserId } = await sendInvitation(params.email);

  const { data: newUser, error } = await supabase
    .from("users")
    .insert({
      id: authUserId,
      restaurant_id: ctx.restaurantId,
      full_name: params.fullName,
      role: params.role,
    })
    .select()
    .single();

  if (error) throw error;

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
  const target = await userRepository.getById(supabase, targetUserId);

  // Guard: laatste eigenaar van een restaurant mag niet gedegradeerd worden.
  if (target.role === "owner" && newRole !== "owner") {
    const ownerCount = await userRepository.countOwners(supabase, ctx.restaurantId);
    if (ownerCount <= 1) {
      throw new Error("Kan de laatste eigenaar van dit restaurant niet degraderen");
    }
  }

  const updated = await userRepository.updateRole(supabase, targetUserId, newRole);

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

  const target = await userRepository.getById(supabase, targetUserId);

  if (target.role === "owner" && !isActive) {
    const ownerCount = await userRepository.countOwners(supabase, ctx.restaurantId);
    if (ownerCount <= 1) {
      throw new Error("Kan de laatste (actieve) eigenaar van dit restaurant niet deactiveren");
    }
  }

  const updated = await userRepository.setActive(supabase, targetUserId, isActive);

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
) {
  if (targetUserId === ctx.userId) {
    throw new Error("Je kan jezelf niet verwijderen");
  }

  const target = await userRepository.getById(supabase, targetUserId);

  if (target.role === "owner") {
    const ownerCount = await userRepository.countOwners(supabase, ctx.restaurantId);
    if (ownerCount <= 1) {
      throw new Error("Kan de laatste eigenaar van dit restaurant niet verwijderen");
    }
  }

  try {
    await userRepository.remove(supabase, targetUserId);
  } catch (err: any) {
    // FK-constraints (activity_log.user_id, audit_log.changed_by) voorkomen hard
    // verwijderen van gebruikers met historie — dat is gewenst gedrag, alleen
    // netjes vertalen naar een begrijpelijke foutmelding i.p.v. ruwe DB-error.
    if (err?.code === "23503") {
      throw new Error(
        "Deze gebruiker heeft al historie (bonnen/facturen/activiteit) en kan niet " +
          "verwijderd worden — deactiveer het account in plaats daarvan"
      );
    }
    throw err;
  }

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `verwijderde ${target.full_name}`,
    target_table: "users",
    target_id: targetUserId,
  });
}
