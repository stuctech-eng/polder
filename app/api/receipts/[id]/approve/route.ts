import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { getApprovalSettings, verifyApproval } from "@/lib/approval/approval-service";
import { z } from "zod";

const approveSchema = z.object({
  credential: z.string().optional(), // PIN bij method=pin, leeg bij restaurant_confirms
});

export async function POST(
  request: Request,
  { params }: { params: { id: string } }
) {
  let ctx;
  try {
    ctx = await requireRole("APPROVE_RECEIPTS");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();

  const body = await request.json().catch(() => ({}));
  const parsed = approveSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { data: receipt } = await supabase
    .from("receipts")
    .select("id, status, open_tabs(company_id)")
    .eq("id", params.id)
    .single();

  if (!receipt) {
    return NextResponse.json({ error: "Bon niet gevonden" }, { status: 404 });
  }
  if (receipt.status !== "pending_approval") {
    return NextResponse.json(
      { error: `Bon heeft status '${receipt.status}', wacht niet op goedkeuring` },
      { status: 400 }
    );
  }

  const companyId = (receipt.open_tabs as any)?.company_id;
  const settings = await getApprovalSettings(supabase, companyId);

  const { data: userProfile } = await supabase
    .from("users")
    .select("full_name")
    .eq("id", ctx.userId)
    .single();

  // De Receipt Manager / deze route kent alleen de Approval Service — geen
  // kennis van PIN-hashing of providerdetails (klant-instructie, sectie 10.7).
  const result = await verifyApproval(settings, {
    credential: parsed.data.credential,
    approverName: userProfile?.full_name ?? "Onbekend",
  });

  if (!result.success) {
    return NextResponse.json({ error: result.reason ?? "Goedkeuring mislukt" }, { status: 400 });
  }

  const newReceiptStatus = settings.autoLock ? "locked" : "approved";

  const { error: receiptUpdateError } = await supabase
    .from("receipts")
    .update({ status: newReceiptStatus })
    .eq("id", params.id);
  if (receiptUpdateError) {
    return NextResponse.json({ error: receiptUpdateError.message }, { status: 500 });
  }

  await supabase
    .from("approvals")
    .update({
      status: "approved",
      approved_by: userProfile?.full_name ?? ctx.userId,
      approved_at: new Date().toISOString(),
    })
    .eq("receipt_id", params.id)
    .eq("status", "pending");

  await supabase.from("domain_events").insert({
    restaurant_id: ctx.restaurantId,
    event_type: "ApprovalCompleted",
    payload: { receipt_id: params.id, company_id: companyId, method: settings.method },
    published_by: ctx.userId,
  });

  if (newReceiptStatus === "locked") {
    await supabase.from("domain_events").insert({
      restaurant_id: ctx.restaurantId,
      event_type: "ReceiptLocked",
      payload: { receipt_id: params.id },
      published_by: ctx.userId,
    });
  }

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `keurde een bon goed (${settings.method})`,
    target_table: "receipts",
    target_id: params.id,
  });

  return NextResponse.json({ status: newReceiptStatus });
}
