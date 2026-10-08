import type { SupabaseClient } from "@supabase/supabase-js";
import type { UserRole } from "./role-helpers";

// Alleen LEZEN met de gebruikersverbinding. Schrijven op `users` gebeurt uitsluitend in user-admin-repository.ts (stap 3).

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
