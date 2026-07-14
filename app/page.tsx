import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { hasPermission } from "@/lib/user-management/permission-service";
import type { UserRole } from "@/lib/user-management/role-helpers";

export default async function RootPage() {
  const supabase = createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    const { data: profile } = await supabase
      .from("users")
      .select("role")
      .eq("id", user.id)
      .single();

    const role = profile?.role as UserRole | undefined;
    if (role && hasPermission(role, "VIEW_DASHBOARD")) {
      redirect("/dashboard");
    }
    // Wie geen dashboard mag zien (bijv. Bediening/Keuken), landt op de
    // pagina die wél bij hun rol past.
    if (role && hasPermission(role, "MANAGE_OPEN_TABS")) {
      redirect("/open-tabs");
    }
  }

  redirect("/dashboard"); // middleware stuurt niet-ingelogde gebruikers alsnog naar /login
}
