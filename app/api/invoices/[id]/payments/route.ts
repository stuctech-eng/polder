import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { z } from "zod";

const paymentSchema = z.object({
  amount: z.number().positive(),
  method: z.string().optional(),
  paidAt: z.string().optional(),
});

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    await requireRole("MANAGE_INVOICES");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();
  const { data, error } = await supabase
    .from("payments")
    .select("*")
    .eq("invoice_id", params.id)
    .order("paid_at", { ascending: false });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({ payments: data });
}

export async function POST(
  request: Request,
  { params }: { params: { id: string } }
) {
  let ctx;
  try {
    ctx = await requireRole("MANAGE_INVOICES");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const body = await request.json();
  const parsed = paymentSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const supabase = createSupabaseServerClient();

  // Tenant-isolatie via RLS-gefilterde select (v1.20-les): geen rij terug
  // = factuur bestaat niet of hoort bij een ander restaurant.
  const { data: invoice } = await supabase
    .from("invoices")
    .select("id, invoice_number, total, status")
    .eq("id", params.id)
    .single();

  if (!invoice) {
    return NextResponse.json({ error: "Factuur niet gevonden" }, { status: 404 });
  }
  if (invoice.status === "paid") {
    return NextResponse.json(
      { error: "Deze factuur staat al op volledig betaald" },
      { status: 400 }
    );
  }

  const { data: payment, error: paymentError } = await supabase
    .from("payments")
    .insert({
      invoice_id: params.id,
      amount: parsed.data.amount,
      method: parsed.data.method || null,
      paid_at: parsed.data.paidAt || new Date().toISOString(),
    })
    .select()
    .single();

  if (paymentError) {
    return NextResponse.json({ error: paymentError.message }, { status: 500 });
  }

  // Guardian Mode: dependency-analyse — na elke betaling controleren of het
  // totaal aan betalingen de factuur volledig dekt, en zo ja automatisch op
  // 'paid' zetten. Voorkomt dat iemand dit los moet bijhouden/vergeten.
  const { data: allPayments } = await supabase
    .from("payments")
    .select("amount")
    .eq("invoice_id", params.id);

  const totalPaid = (allPayments ?? []).reduce((sum, p) => sum + Number(p.amount), 0);
  const isFullyPaid = totalPaid >= Number(invoice.total) - 0.005; // afronding

  if (isFullyPaid) {
    await supabase.from("invoices").update({ status: "paid" }).eq("id", params.id);
  } else if (invoice.status === "draft") {
    // Een gedeeltelijke betaling op een nog-niet-verzonden factuur is
    // ongebruikelijk maar niet onmogelijk — zet 'm in ieder geval op 'sent'
    // zodat de status niet misleidend op 'draft' blijft staan.
    await supabase.from("invoices").update({ status: "sent" }).eq("id", params.id);
  }

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `registreerde een betaling van €${parsed.data.amount.toFixed(2)} op factuur ${invoice.invoice_number}${isFullyPaid ? " (volledig betaald)" : ""}`,
    target_table: "payments",
    target_id: payment.id,
  });

  return NextResponse.json(
    { payment, isFullyPaid, totalPaid, remaining: Math.max(0, Number(invoice.total) - totalPaid) },
    { status: 201 }
  );
}
