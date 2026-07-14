import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
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
  try {
    await requireRole("MANAGE_OPEN_TABS");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

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
  let ctx;
  try {
    ctx = await requireRole("MANAGE_OPEN_TABS");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();

  const body = await request.json();
  const parsed = openTabSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  // Guardian Mode: tenant-isolatie handhaven — RLS beschermt hier niet automatisch,
  // want restaurant_id wordt door de server zelf gezet (op basis van de eigen sessie),
  // niet afgeleid van het gekoppelde bedrijf. Zonder deze check zou iemand in theorie
  // een company_id van een ANDER restaurant kunnen invullen en toch laten slagen.
  if (parsed.data.companyId) {
    const { data: company } = await supabase
      .from("companies")
      .select("id")
      .eq("id", parsed.data.companyId)
      .single();
    // RLS filtert deze select al op eigen restaurant — als er niets terugkomt,
    // bestaat het bedrijf niet of hoort het bij een ander restaurant.
    if (!company) {
      return NextResponse.json({ error: "Bedrijf niet gevonden" }, { status: 400 });
    }

    for (const [field, table] of [
      ["departmentId", "departments"],
      ["costCenterId", "cost_centers"],
      ["projectId", "projects"],
    ] as const) {
      const value = parsed.data[field];
      if (value) {
        const { data: related } = await supabase
          .from(table)
          .select("id")
          .eq("id", value)
          .eq("company_id", parsed.data.companyId)
          .single();
        if (!related) {
          return NextResponse.json(
            { error: `Gekoppeld item (${field}) hoort niet bij dit bedrijf` },
            { status: 400 }
          );
        }
      }
    }
  }

  const { data, error } = await supabase
    .from("open_tabs")
    .insert({
      restaurant_id: ctx.restaurantId,
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
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: "opende een nieuwe rekening",
    target_table: "open_tabs",
    target_id: data.id,
  });

  // Event Bus: TabOpened (governance 6.1 — stabiel event-contract)
  await supabase.from("domain_events").insert({
    restaurant_id: ctx.restaurantId,
    event_type: "TabOpened",
    payload: { open_tab_id: data.id, company_id: data.company_id },
    published_by: ctx.userId,
  });

  return NextResponse.json({ openTab: data }, { status: 201 });
}
