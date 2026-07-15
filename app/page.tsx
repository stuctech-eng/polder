import { redirect } from "next/navigation";
import { getCurrentUserContext } from "@/lib/user-management/session-context";
import { hasPermission } from "@/lib/user-management/permission-service";

export default async function RootPage() {
  const ctx = await getCurrentUserContext();

  if (ctx) {
    if (hasPermission(ctx.role, "VIEW_DASHBOARD")) {
      redirect("/dashboard");
    }
    // Wie geen dashboard mag zien (bijv. Bediening/Keuken), landt op de
    // pagina die wél bij hun rol past.
    if (hasPermission(ctx.role, "MANAGE_OPEN_TABS")) {
      redirect("/open-tabs");
    }
  }

  redirect("/dashboard"); // middleware stuurt niet-ingelogde gebruikers alsnog naar /login
}
