import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { companySchema } from "@/lib/validation/company";

/**
 * API-first ontwerp (sectie 1): deze route is de enige plek waar
 * bedrijfslogica voor Bedrijvenbeheer leeft. De webinterface en
 * eventuele toekomstige apps gebruiken beide deze route.
 */

export async function GET() {
  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Niet ingelogd" }, { status: 401 });
  }

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
  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Niet ingelogd" }, { status: 401 });
  }

  const body = await request.json();
  const parsed = companySchema.safeParse(body);

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
    .from("companies")
    .insert({
      restaurant_id: profile.restaurant_id,
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
    restaurant_id: profile.restaurant_id,
    user_id: userData.user.id,
    action: `maakte bedrijf "${data.name}" aan`,
    target_table: "companies",
    target_id: data.id,
  });

  return NextResponse.json({ company: data }, { status: 201 });
}
