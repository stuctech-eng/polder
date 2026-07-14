import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { z } from "zod";

const workflowRuleSchema = z.object({
  invoiceFrequency: z.enum(["immediate", "weekly", "monthly", "per_project"]),
  requiresApproval: z.boolean(),
});

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();
  const { data, error } = await supabase
    .from("workflow_rules")
    .select("*")
    .eq("company_id", params.id)
    .maybeSingle();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({ workflowRule: data });
}

export async function PUT(
  request: Request,
  { params }: { params: { id: string } }
) {
  let ctx;
  try {
    ctx = await requireRole("MANAGE_SETTINGS");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();

  const body = await request.json();
  const parsed = workflowRuleSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  // Guardian Mode: tenant-isolatie — verifieer dat dit bedrijf echt bij het eigen
  // restaurant hoort vóórdat we een workflow_rules-rij eraan koppelen (RLS op
  // workflow_rules zelf checkt alleen de eigen restaurant_id-kolom, niet company_id).
  const { data: company } = await supabase
    .from("companies")
    .select("id")
    .eq("id", params.id)
    .single();
  if (!company) {
    return NextResponse.json({ error: "Bedrijf niet gevonden" }, { status: 404 });
  }

  // Config-driven (governance 6.1/6.3): één regel per bedrijf, upsert i.p.v. maatwerkcode
  const { data: existing } = await supabase
    .from("workflow_rules")
    .select("id")
    .eq("company_id", params.id)
    .maybeSingle();

  let result;
  if (existing) {
    result = await supabase
      .from("workflow_rules")
      .update({
        invoice_frequency: parsed.data.invoiceFrequency,
        requires_approval: parsed.data.requiresApproval,
      })
      .eq("id", existing.id)
      .select()
      .single();
  } else {
    result = await supabase
      .from("workflow_rules")
      .insert({
        restaurant_id: ctx.restaurantId,
        company_id: params.id,
        invoice_frequency: parsed.data.invoiceFrequency,
        requires_approval: parsed.data.requiresApproval,
      })
      .select()
      .single();
  }

  if (result.error) {
    return NextResponse.json({ error: result.error.message }, { status: 500 });
  }

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `stelde facturatieregel in (${parsed.data.invoiceFrequency})`,
    target_table: "workflow_rules",
    target_id: result.data.id,
  });

  return NextResponse.json({ workflowRule: result.data });
}
