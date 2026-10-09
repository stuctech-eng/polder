import { createClient } from "@supabase/supabase-js";
export function createSupabaseAdminClient() { return (createClient as any)("x", "service"); }
