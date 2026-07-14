import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getApprovalSettings } from "@/lib/approval/approval-service";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";

export async function POST(
  request: Request,
  { params }: { params: { id: string } }
) {
  let ctx;
  try {
    ctx = await requireRole("MANAGE_RECEIPTS");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();

  // Tenant-isolatie via RLS-gefilterde select (zie v1.20-les): geen rij
  // terug = bon bestaat niet of hoort bij een ander restaurant.
  const { data: receipt } = await supabase
    .from("receipts")
    .select("id, status, open_tab_id, restaurant_id, open_tabs(company_id)")
    .eq("id", params.id)
    .single();

  if (!receipt) {
    return NextResponse.json({ error: "Bon niet gevonden" }, { status: 404 });
  }
  if (!["draft", "linked"].includes(receipt.status)) {
    return NextResponse.json(
      { error: `Bon heeft status '${receipt.status}', kan geen goedkeuring aanvragen` },
      { status: 400 }
    );
  }

  const companyId = (receipt.open_tabs as any)?.company_id;
  if (!companyId) {
    return NextResponse.json(
      { error: "Bon heeft geen gekoppeld bedrijf, kan geen goedkeuring aanvragen" },
      { status: 400 }
    );
  }

  const settings = await getApprovalSettings(supabase, companyId);
  if (!settings.enabled || !settings.method) {
    return NextResponse.json(
      { error: "Goedkeuring is niet ingeschakeld voor dit bedrijf" },
      { status: 400 }
    );
  }

  const { error: updateError } = await supabase
    .from("receipts")
    .update({ status: "pending_approval" })
    .eq("id", params.id);
  if (updateError) {
    return NextResponse.json({ error: updateError.message }, { status: 500 });
  }

  const { error: approvalError } = await supabase.from("approvals").insert({
    receipt_id: params.id,
    company_id: companyId,
    method: settings.method,
    status: "pending",
  });
  if (approvalError) {
    return NextResponse.json({ error: approvalError.message }, { status: 500 });
  }

  await supabase.from("domain_events").insert({
    restaurant_id: ctx.restaurantId,
    event_type: "ApprovalRequested",
    payload: { receipt_id: params.id, company_id: companyId, method: settings.method },
    published_by: ctx.userId,
  });

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: "vroeg goedkeuring aan voor een bon",
    target_table: "receipts",
    target_id: params.id,
  });

  return NextResponse.json({ status: "pending_approval", method: settings.method });
}
