import { createSupabaseServerClient } from "@/lib/supabase/server";
import NewOpenTabForm from "./form";

export default async function NewOpenTabPage() {
  const supabase = createSupabaseServerClient();
  const { data: companies } = await supabase
    .from("companies")
    .select("id, name")
    .eq("is_active", true)
    .order("name");

  return <NewOpenTabForm companies={companies ?? []} />;
}
