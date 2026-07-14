import type { SupabaseClient } from "@supabase/supabase-js";
import type { UserRole } from "./role-helpers";

export interface TeamMember {
  id: string;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  two_factor_enabled: boolean;
  created_at: string;
  email?: string;
}

export async function listByRestaurant(
  supabase: SupabaseClient,
  restaurantId: string
): Promise<TeamMember[]> {
  const { data, error } = await supabase
    .from("users")
    .select("id, full_name, role, is_active, two_factor_enabled, created_at")
    .eq("restaurant_id", restaurantId)
    .order("created_at");

  if (error) throw error;
  return data as TeamMember[];
}

export async function countOwners(supabase: SupabaseClient, restaurantId: string): Promise<number> {
  const { count, error } = await supabase
    .from("users")
    .select("id", { count: "exact", head: true })
    .eq("restaurant_id", restaurantId)
    .eq("role", "owner")
    .eq("is_active", true);

  if (error) throw error;
  return count ?? 0;
}

export async function getById(supabase: SupabaseClient, userId: string) {
  const { data, error } = await supabase
    .from("users")
    .select("id, full_name, role, is_active, restaurant_id")
    .eq("id", userId)
    .single();

  if (error) throw error;
  return data;
}

export async function updateRole(supabase: SupabaseClient, userId: string, role: UserRole) {
  const { data, error } = await supabase
    .from("users")
    .update({ role, updated_at: new Date().toISOString() })
    .eq("id", userId)
    .select()
    .single();

  if (error) throw error;
  return data;
}

export async function setActive(supabase: SupabaseClient, userId: string, isActive: boolean) {
  const { data, error } = await supabase
    .from("users")
    .update({ is_active: isActive, updated_at: new Date().toISOString() })
    .eq("id", userId)
    .select()
    .single();

  if (error) throw error;
  return data;
}

export async function remove(supabase: SupabaseClient, userId: string) {
  const { error } = await supabase.from("users").delete().eq("id", userId);
  if (error) throw error;
}
