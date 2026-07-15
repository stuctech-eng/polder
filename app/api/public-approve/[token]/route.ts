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

  const { data: approval, error: approvalError } = await supabase
    .from("approvals")
    .select("id, status, receipt_id, company_id, method")
    .eq("verification_code", params.token)
    .maybeSingle();

  if (!approval) {
    return NextResponse.json(
      {
        error: "Ongeldige of verlopen link",
        // Tijdelijk voor diagnose — verwijderen zodra bevestigd (v1.35-vervolg)
        debugToken: params.token,
        debugSupabaseError: approvalError?.message ?? null,
      },
      { status: 404 }
    );
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

  const { error: receiptError } = await supabase
    .from("receipts")
    .update({ status: "locked" })
    .eq("id", receipt.id);
  if (receiptError) {
    return NextResponse.json({ error: receiptError.message }, { status: 500 });
  }

  await supabase
    .from("approvals")
    .update({ status: "approved", approved_at: new Date().toISOString(), approved_by: "extern (via link)" })
    .eq("id", approval.id);

  await supabase.from("domain_events").insert({
    restaurant_id: receipt.restaurant_id,
    event_type: "ApprovalCompleted",
    payload: { receipt_id: receipt.id, company_id: approval.company_id, method: "email_or_qr_link" },
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
    action: "keurde een bon goed via externe link (e-mail/QR)",
    target_table: "receipts",
    target_id: receipt.id,
  });

  return NextResponse.json({ status: "locked" });
}
