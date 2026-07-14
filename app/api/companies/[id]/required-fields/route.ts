import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { z } from "zod";

const schema = z.object({
  receiptFields: z.record(z.boolean()),
});

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();
  const { data, error } = await supabase
    .from("configurations")
    .select("value")
    .eq("company_id", params.id)
    .eq("key", "receipt_fields")
    .maybeSingle();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({ receiptFields: data?.value ?? {} });
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
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  // Tenant-isolatie: bevestig dat dit bedrijf bij het eigen restaurant hoort
  // (zelfde les als v1.20 — RLS op 'configurations' checkt alleen restaurant_id,
  // niet de relatie naar companies).
  const { data: company } = await supabase
    .from("companies")
    .select("id")
    .eq("id", params.id)
    .single();
  if (!company) {
    return NextResponse.json({ error: "Bedrijf niet gevonden" }, { status: 404 });
  }

  const { data: existing } = await supabase
    .from("configurations")
    .select("id")
    .eq("company_id", params.id)
    .eq("key", "receipt_fields")
    .maybeSingle();

  let result;
  if (existing) {
    result = await supabase
      .from("configurations")
      .update({ value: parsed.data.receiptFields })
      .eq("id", existing.id)
      .select()
      .single();
  } else {
    result = await supabase
      .from("configurations")
      .insert({
        restaurant_id: ctx.restaurantId,
        company_id: params.id,
        key: "receipt_fields",
        value: parsed.data.receiptFields,
      })
      .select()
      .single();
  }

  if (result.error) {
    return NextResponse.json({ error: result.error.message }, { status: 500 });
  }

  return NextResponse.json({ receiptFields: result.data.value });
}
