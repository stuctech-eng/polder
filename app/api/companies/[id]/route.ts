import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { companyUpdateSchema } from "@/lib/validation/company";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    await requireRole("MANAGE_COMPANIES");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();

  const { data, error } = await supabase
    .from("companies")
    .select("*")
    .eq("id", params.id)
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 404 });
  }

  return NextResponse.json({ company: data });
}

export async function PATCH(
  request: Request,
  { params }: { params: { id: string } }
) {
  let ctx;
  try {
    ctx = await requireRole("MANAGE_COMPANIES");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();

  const body = await request.json();
  const parsed = companyUpdateSchema.safeParse(body);

  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { data, error } = await supabase
    .from("companies")
    .update({
      name: parsed.data.name,
      address: parsed.data.address,
      vat_number: parsed.data.vatNumber,
      coc_number: parsed.data.cocNumber,
      invoice_email: parsed.data.invoiceEmail || null,
      payment_term_days: parsed.data.paymentTermDays,
      notes: parsed.data.notes,
      ...(parsed.data.isActive !== undefined ? { is_active: parsed.data.isActive } : {}),
      updated_at: new Date().toISOString(),
    })
    .eq("id", params.id)
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `wijzigde bedrijf "${data.name}"`,
    target_table: "companies",
    target_id: data.id,
  });

  return NextResponse.json({ company: data });
}
