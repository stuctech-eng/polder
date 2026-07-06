import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { z } from "zod";

const updateSchema = z.object({
  status: z.enum(["open", "closed", "invoiced"]).optional(),
  tableNumber: z.string().optional(),
  guestCount: z.number().int().positive().optional(),
});

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();

  const { data, error } = await supabase
    .from("open_tabs")
    .select("*, companies(name), departments(name), cost_centers(name), projects(name)")
    .eq("id", params.id)
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 404 });
  }
  return NextResponse.json({ openTab: data });
}

export async function PATCH(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Niet ingelogd" }, { status: 401 });
  }

  const body = await request.json();
  const parsed = updateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { data: profile } = await supabase
    .from("users")
    .select("restaurant_id")
    .eq("id", userData.user.id)
    .single();

  const updates: Record<string, unknown> = {};
  if (parsed.data.status) {
    updates.status = parsed.data.status;
    if (parsed.data.status === "closed") {
      updates.closed_at = new Date().toISOString();
    }
  }
  if (parsed.data.tableNumber !== undefined) updates.table_number = parsed.data.tableNumber;
  if (parsed.data.guestCount !== undefined) updates.guest_count = parsed.data.guestCount;

  const { data, error } = await supabase
    .from("open_tabs")
    .update(updates)
    .eq("id", params.id)
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  if (profile && parsed.data.status === "closed") {
    await supabase.from("activity_log").insert({
      restaurant_id: profile.restaurant_id,
      user_id: userData.user.id,
      action: "sloot een rekening",
      target_table: "open_tabs",
      target_id: data.id,
    });

    // Event Bus: TabClosed
    await supabase.from("domain_events").insert({
      restaurant_id: profile.restaurant_id,
      event_type: "TabClosed",
      payload: { open_tab_id: data.id },
      published_by: userData.user.id,
    });
  }

  return NextResponse.json({ openTab: data });
}
