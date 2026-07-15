import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { z } from "zod";

const updateSchema = z.object({
  status: z.enum(["sent", "paid", "overdue"]),
});

export async function PATCH(
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
  const parsed = updateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const supabase = createSupabaseServerClient();

  // Guardian Mode: alleen zinvolle overgangen toestaan — een factuur die al
  // 'paid' is mag niet handmatig teruggezet worden naar 'sent' via deze route
  // (voorkomt inconsistentie met de betalingshistorie); 'draft' is een
  // startstatus, niet iets om handmatig naartoe te zetten.
  const { data: current } = await supabase
    .from("invoices")
    .select("status, invoice_number")
    .eq("id", params.id)
    .single();

  if (!current) {
    return NextResponse.json({ error: "Factuur niet gevonden" }, { status: 404 });
  }
  if (current.status === "paid" && parsed.data.status !== "paid") {
    return NextResponse.json(
      { error: "Een betaalde factuur kan niet teruggezet worden — corrigeer via een betaling" },
      { status: 400 }
    );
  }

  const { data, error } = await supabase
    .from("invoices")
    .update({ status: parsed.data.status })
    .eq("id", params.id)
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `zette factuur ${current.invoice_number} op status '${parsed.data.status}'`,
    target_table: "invoices",
    target_id: params.id,
  });

  return NextResponse.json({ invoice: data });
}
