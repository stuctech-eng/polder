import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { z } from "zod";

const updateSchema = z.object({
  status: z.literal("closed").optional(), // 'invoiced' gebeurt alleen via generate-invoice
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

export async function DELETE(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Niet ingelogd" }, { status: 401 });
  }

  const { data: tab } = await supabase
    .from("open_tabs")
    .select("status")
    .eq("id", params.id)
    .single();

  if (!tab) {
    return NextResponse.json({ error: "Rekening niet gevonden" }, { status: 404 });
  }
  if (tab.status !== "open") {
    return NextResponse.json(
      { error: "Alleen open (nog niet gesloten) rekeningen kunnen verwijderd worden" },
      { status: 400 }
    );
  }

  const { count } = await supabase
    .from("receipts")
    .select("id", { count: "exact", head: true })
    .eq("open_tab_id", params.id);

  if ((count ?? 0) > 0) {
    return NextResponse.json(
      { error: "Rekening heeft gekoppelde bonnen, kan niet verwijderd worden" },
      { status: 400 }
    );
  }

  const { data: profile } = await supabase
    .from("users")
    .select("restaurant_id")
    .eq("id", userData.user.id)
    .single();

  const { error } = await supabase.from("open_tabs").delete().eq("id", params.id);
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  if (profile) {
    await supabase.from("activity_log").insert({
      restaurant_id: profile.restaurant_id,
      user_id: userData.user.id,
      action: "verwijderde een lege open rekening",
      target_table: "open_tabs",
      target_id: params.id,
    });
  }

  return NextResponse.json({ success: true });
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

  // Guardian Mode: impact-analyse — een gefactureerde rekening is onveranderlijk.
  // Zonder deze check zou de UI-verberging (client-side) de enige bescherming zijn,
  // en dat is nooit voldoende (zie v1.18-les).
  const { data: currentTab } = await supabase
    .from("open_tabs")
    .select("status")
    .eq("id", params.id)
    .single();

  if (currentTab?.status === "invoiced") {
    return NextResponse.json(
      { error: "Deze rekening is al gefactureerd en kan niet meer gewijzigd worden" },
      { status: 400 }
    );
  }

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
 
