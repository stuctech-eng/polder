import { NextResponse } from "next/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";

/**
 * Publieke route — bewust GEEN requireRole(), want er is geen sessie.
 * De beveiliging zit in de token zelf (niet-raadbaar, eenmalig, gekoppeld
 * aan precies één bon). Gebruikt de service-role client omdat er geen
 * ingelogde gebruiker is om RLS namens te laten gelden.
 */
export async function GET(
  request: Request,
  { params }: { params: { token: string } }
) {
  const supabase = createSupabaseAdminClient();

  const { data: approval } = await supabase
    .from("approvals")
    .select("id, status, receipt_id, company_id, method")
    .eq("verification_code", params.token)
    .maybeSingle();

  if (!approval) {
    return NextResponse.json({ error: "Ongeldige of verlopen link" }, { status: 404 });
  }

  const { data: receipt } = await supabase
    .from("receipts")
    .select("id, status, total, receipt_number, receipt_date, receipt_lines(*)")
    .eq("id", approval.receipt_id)
    .single();

  const { data: company } = await supabase
    .from("companies")
    .select("name")
    .eq("id", approval.company_id)
    .single();

  return NextResponse.json({
    approvalStatus: approval.status,
    receipt,
    companyName: company?.name ?? "Onbekend bedrijf",
  });
}

export async function POST(
  request: Request,
  { params }: { params: { token: string } }
) {
  const supabase = createSupabaseAdminClient();

  const body = await request.json().catch(() => ({}));
  const action: "approve" | "reject" = body.action === "reject" ? "reject" : "approve";
  const approverName: string = (body.approverName || "").trim();
  const reason: string | undefined = body.reason?.trim() || undefined;

  if (!approverName) {
    return NextResponse.json({ error: "Naam is verplicht" }, { status: 400 });
  }

  const { data: approval } = await supabase
    .from("approvals")
    .select("id, status, receipt_id, company_id")
    .eq("verification_code", params.token)
    .maybeSingle();

  if (!approval) {
    return NextResponse.json({ error: "Ongeldige of verlopen link" }, { status: 404 });
  }
  if (approval.status !== "pending") {
    return NextResponse.json(
      { error: `Deze goedkeuring is al verwerkt (status: ${approval.status})` },
      { status: 400 }
    );
  }

  const { data: receipt } = await supabase
    .from("receipts")
    .select("id, status, restaurant_id")
    .eq("id", approval.receipt_id)
    .single();

  if (!receipt || receipt.status !== "pending_approval") {
    return NextResponse.json(
      { error: "Deze bon wacht niet meer op goedkeuring" },
      { status: 400 }
    );
  }

  if (action === "approve") {
    const { error: receiptError } = await supabase
      .from("receipts")
      .update({ status: "locked" })
      .eq("id", receipt.id);
    if (receiptError) {
      return NextResponse.json({ error: receiptError.message }, { status: 500 });
    }

    await supabase
      .from("approvals")
      .update({ status: "approved", approved_at: new Date().toISOString(), approved_by: approverName })
      .eq("id", approval.id);

    await supabase.from("domain_events").insert({
      restaurant_id: receipt.restaurant_id,
      event_type: "ApprovalCompleted",
      payload: { receipt_id: receipt.id, company_id: approval.company_id, approved_by: approverName },
      published_by: null,
    });
    await supabase.from("domain_events").insert({
      restaurant_id: receipt.restaurant_id,
      event_type: "ReceiptLocked",
      payload: { receipt_id: receipt.id },
      published_by: null,
    });

    await supabase.from("activity_log").insert({
      restaurant_id: receipt.restaurant_id,
      user_id: null,
      action: `${approverName} keurde een bon goed via externe link (e-mail/QR)`,
      target_table: "receipts",
      target_id: receipt.id,
    });

    return NextResponse.json({ status: "locked" });
  }

  // action === "reject": bon terug naar 'linked' zodat personeel 'm kan
  // corrigeren en eventueel opnieuw ter goedkeuring kan aanbieden.
  const { error: receiptError } = await supabase
    .from("receipts")
    .update({ status: "linked" })
    .eq("id", receipt.id);
  if (receiptError) {
    return NextResponse.json({ error: receiptError.message }, { status: 500 });
  }

  await supabase
    .from("approvals")
    .update({
      status: "rejected",
      approved_at: new Date().toISOString(),
      approved_by: approverName,
      metadata: reason ? { reason } : null,
    })
    .eq("id", approval.id);

  await supabase.from("domain_events").insert({
    restaurant_id: receipt.restaurant_id,
    event_type: "ApprovalRejected",
    payload: { receipt_id: receipt.id, company_id: approval.company_id, rejected_by: approverName, reason },
    published_by: null,
  });

  await supabase.from("activity_log").insert({
    restaurant_id: receipt.restaurant_id,
    user_id: null,
    action: `${approverName} wees een bon af via externe link${reason ? `: "${reason}"` : ""}`,
    target_table: "receipts",
    target_id: receipt.id,
  });

  return NextResponse.json({ status: "linked" });
}
