import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import TeamManagementUI from "./team-management-ui";

export default async function TeamPage() {
  let team;
  let permissionError: string | null = null;

  try {
    const ctx = await requireRole("MANAGE_TEAM");
    const supabase = createSupabaseServerClient();
    const { data } = await supabase
      .from("users")
      .select("id, full_name, role, is_active, two_factor_enabled, created_at")
      .eq("restaurant_id", ctx.restaurantId)
      .order("created_at");
    team = data ?? [];
  } catch (err) {
    if (err instanceof PermissionError) {
      permissionError = err.message;
    } else {
      permissionError = "Onbekende fout";
    }
  }

  if (permissionError) {
    return (
      <main className="p-4 max-w-2xl mx-auto">
        <h1 className="text-xl font-semibold mb-4">Team</h1>
        <p className="text-sm text-red-600" role="alert">
          {permissionError}
        </p>
      </main>
    );
  }

  return <TeamManagementUI initialTeam={team ?? []} />;
}
