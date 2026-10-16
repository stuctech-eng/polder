import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getApprovalSettings, notifyApprovalRequested, submitForApproval } from "@/lib/approval/approval-service";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { requireFeature } from "@/lib/features/feature-service";

export async function POST(
  request: Request,
  { params }: { params: { id: string } }
) {
  let ctx;
  try {
    ctx = await requireRole("MANAGE_RECEIPTS");
    await requireFeature("approval");
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
    .select("id, status, total, open_tab_id, restaurant_id, open_tabs(company_id)")
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

  // Indienen in een keer (bon + regel, methode uit de bedrijfsinstelling); lukt het niet, dan is er niets gewijzigd.
  const submitted = await submitForApproval(supabase, params.id);
  if (!submitted.ok) {
    if (submitted.settingChanged) {
      return NextResponse.json(
        { error: "De goedkeuringsinstelling van dit bedrijf is net gewijzigd. Probeer het opnieuw." },
        { status: 409 }
      );
    }
    return NextResponse.json({ error: submitted.error }, { status: 500 });
  }
  const method = submitted.method;
  if (!method) {
    return NextResponse.json(
      { error: "Goedkeuring is niet ingeschakeld voor dit bedrijf" },
      { status: 400 }
    );
  }
  const approvalToken = submitted.approvalToken;

  let approvalWarning: string | null = null;
  if (method === "email") {
    const settings = await getApprovalSettings(supabase, companyId);
    const { data: restaurant } = await supabase
      .from("restaurants")
      .select("name")
      .eq("id", ctx.restaurantId)
      .single();
    const notifyResult = await notifyApprovalRequested({
      settings: { ...settings, method },
      token: approvalToken!,
      restaurantName: restaurant?.name ?? "Restaurant",
      receiptTotal: Number(receipt.total ?? 0),
      baseUrl: process.env.NEXT_PUBLIC_SITE_URL || "https://polder.vercel.app",
    });
    if (!notifyResult.success) {
      approvalWarning = notifyResult.warning ?? "Kon goedkeuringsmail niet versturen";
    }
  }

  await supabase.from("domain_events").insert({
    restaurant_id: ctx.restaurantId,
    event_type: "ApprovalRequested",
    payload: { receipt_id: params.id, company_id: companyId, method },
    published_by: ctx.userId,
  });

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: "vroeg goedkeuring aan voor een bon",
    target_table: "receipts",
    target_id: params.id,
  });

  return NextResponse.json({
    status: "pending_approval",
    method,
    approvalToken,
    approvalWarning,
  });
}
