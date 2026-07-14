import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import NewOpenTabForm from "./form";

export default async function NewOpenTabPage() {
  try {
    await requireRole("MANAGE_OPEN_TABS");
  } catch (err) {
    return (
      <main className="p-4 max-w-2xl mx-auto">
        <p className="text-sm text-red-600" role="alert">
          {err instanceof PermissionError ? err.message : "Onbekende fout"}
        </p>
      </main>
    );
  }

  const supabase = createSupabaseServerClient();
  const { data: companies } = await supabase
    .from("companies")
    .select("id, name")
    .eq("is_active", true)
    .order("name");

  return <NewOpenTabForm companies={companies ?? []} />;
}
