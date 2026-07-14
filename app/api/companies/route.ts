import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { companySchema } from "@/lib/validation/company";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";

/**
 * API-first ontwerp (sectie 1): deze route is de enige plek waar
 * bedrijfslogica voor Bedrijvenbeheer leeft. De webinterface en
 * eventuele toekomstige apps gebruiken beide deze route.
 */

export async function GET() {
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
    .order("name", { ascending: true });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ companies: data });
}

export async function POST(request: Request) {
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
  const parsed = companySchema.safeParse(body);

  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { data, error } = await supabase
    .from("companies")
    .insert({
      restaurant_id: ctx.restaurantId,
      name: parsed.data.name,
      address: parsed.data.address,
      vat_number: parsed.data.vatNumber,
      coc_number: parsed.data.cocNumber,
      invoice_email: parsed.data.invoiceEmail || null,
      payment_term_days: parsed.data.paymentTermDays,
      notes: parsed.data.notes,
    })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  // Activity Log: vanaf dag 1 verplicht (blueprint sectie "Audit & Activity Engine")
  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `maakte bedrijf "${data.name}" aan`,
    target_table: "companies",
    target_id: data.id,
  });

  return NextResponse.json({ company: data }, { status: 201 });
}
