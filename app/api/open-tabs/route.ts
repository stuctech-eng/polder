import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { z } from "zod";

const openTabSchema = z.object({
  companyId: z.string().uuid().optional().or(z.literal("")),
  departmentId: z.string().uuid().optional().or(z.literal("")),
  costCenterId: z.string().uuid().optional().or(z.literal("")),
  projectId: z.string().uuid().optional().or(z.literal("")),
  tableNumber: z.string().optional(),
  guestCount: z.number().int().positive().optional(),
});

export async function GET(request: Request) {
  const supabase = createSupabaseServerClient();
  const { searchParams } = new URL(request.url);
  const status = searchParams.get("status") || "open";

  const { data, error } = await supabase
    .from("open_tabs")
    .select("*, companies(name)")
    .eq("status", status)
    .order("opened_at", { ascending: false });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({ openTabs: data });
}

export async function POST(request: Request) {
  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Niet ingelogd" }, { status: 401 });
  }

  const body = await request.json();
  const parsed = openTabSchema.safeParse(body);
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

  if (!profile) {
    return NextResponse.json({ error: "Geen restaurantprofiel gevonden" }, { status: 400 });
  }

  const { data, error } = await supabase
    .from("open_tabs")
    .insert({
      restaurant_id: profile.restaurant_id,
      company_id: parsed.data.companyId || null,
      department_id: parsed.data.departmentId || null,
      cost_center_id: parsed.data.costCenterId || null,
      project_id: parsed.data.projectId || null,
      table_number: parsed.data.tableNumber || null,
      guest_count: parsed.data.guestCount || null,
      status: "open",
    })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabase.from("activity_log").insert({
    restaurant_id: profile.restaurant_id,
    user_id: userData.user.id,
    action: "opende een nieuwe rekening",
    target_table: "open_tabs",
    target_id: data.id,
  });

  // Event Bus: TabOpened (governance 6.1 — stabiel event-contract)
  await supabase.from("domain_events").insert({
    restaurant_id: profile.restaurant_id,
    event_type: "TabOpened",
    payload: { open_tab_id: data.id, company_id: data.company_id },
    published_by: userData.user.id,
  });

  return NextResponse.json({ openTab: data }, { status: 201 });
}
