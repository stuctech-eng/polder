import { createClient } from "@supabase/supabase-js";
export function createSupabaseServerClient() { return (createClient as any)("x", "user:" + (globalThis as any).__cur.id); }
