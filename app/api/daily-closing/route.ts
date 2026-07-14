import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { buildDailyClosingReport } from "@/lib/daily-closing/daily-closing-service";

export async function GET(request: Request) {
  try {
    const ctx = await requireRole("VIEW_DAILY_CLOSING");
    const supabase = createSupabaseServerClient();

    const { searchParams } = new URL(request.url);
    const date = searchParams.get("date") || new Date().toISOString().slice(0, 10);

    const report = await buildDailyClosingReport(supabase, ctx.restaurantId, date);
    return NextResponse.json({ report });
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const ctx = await requireRole("EXECUTE_DAILY_CLOSING");
    const supabase = createSupabaseServerClient();

    const body = await request.json().catch(() => ({}));
    const date = body.date || new Date().toISOString().slice(0, 10);

    const report = await buildDailyClosingReport(supabase, ctx.restaurantId, date);

    if (report.alreadyClosed) {
      return NextResponse.json({ error: "Deze dag is al afgesloten" }, { status: 400 });
    }

    const { data: closing, error } = await supabase
      .from("daily_closings")
      .insert({
        restaurant_id: ctx.restaurantId,
        closing_date: date,
        closed_by: ctx.userId,
        total_revenue: report.totalRevenue,
        business_revenue: report.businessRevenue,
        notes: body.notes || null,
      })
      .select()
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    await supabase.from("domain_events").insert({
      restaurant_id: ctx.restaurantId,
      event_type: "DayClosed",
      payload: { daily_closing_id: closing.id, date, total_revenue: report.totalRevenue },
      published_by: ctx.userId,
    });

    await supabase.from("activity_log").insert({
      restaurant_id: ctx.restaurantId,
      user_id: ctx.userId,
      action: `sloot de dag van ${date} af (€${report.totalRevenue.toFixed(2)} omzet)`,
      target_table: "daily_closings",
      target_id: closing.id,
    });

    return NextResponse.json({ closing }, { status: 201 });
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }
}
