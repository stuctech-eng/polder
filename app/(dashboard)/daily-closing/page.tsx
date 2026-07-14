import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { buildDailyClosingReport } from "@/lib/daily-closing/daily-closing-service";
import DailyClosingUI from "./daily-closing-ui";

export default async function DailyClosingPage() {
  let report;
  let permissionError: string | null = null;

  try {
    const ctx = await requireRole("VIEW_DAILY_CLOSING");
    const supabase = createSupabaseServerClient();
    const today = new Date().toISOString().slice(0, 10);
    report = await buildDailyClosingReport(supabase, ctx.restaurantId, today);
  } catch (err) {
    permissionError = err instanceof PermissionError ? err.message : "Onbekende fout";
  }

  if (permissionError || !report) {
    return (
      <main className="p-4 max-w-2xl mx-auto">
        <h1 className="text-xl font-semibold mb-4">Dagafsluiting</h1>
        <p className="text-sm text-red-600" role="alert">
          {permissionError}
        </p>
      </main>
    );
  }

  return <DailyClosingUI initialReport={report} />;
}
