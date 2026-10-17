import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { requireFeature } from "@/lib/features/feature-service";
import { checkSignatureInput, signErrorResponse } from "@/lib/approval/signature";

/**
 * Stap 14c: de klant tekent de bon op het toestel van het restaurant. De bediening start dit: MANAGE_RECEIPTS is genoeg,
 * er wordt GEEN APPROVE_RECEIPTS gegeven. Bon en goedkeuringsregel worden in EEN databasetransactie bijgewerkt door
 * bon_ondertekenen (migratie 0047), die zelf rol, restaurant, module, methode, bonstatus en vingerafdruk controleert.
 * Volgorde: requireRole -> requireFeature (approval, signature) -> invoer -> database.
 */
export async function POST(request: Request, { params }: { params: { id: string } }) {
  let ctx;
  try {
    ctx = await requireRole("MANAGE_RECEIPTS");
    await requireFeature("approval");
    await requireFeature("signature");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const body = await request.json().catch(() => null);
  const input = checkSignatureInput(body);
  if (!input.ok) {
    return NextResponse.json({ error: input.error }, { status: 400 });
  }

  const supabase = createSupabaseServerClient();
  const { data, error } = await supabase.rpc("bon_ondertekenen", {
    p_bon: params.id,
    p_naam: input.value.name,
    p_handtekening: input.value.signature,
    p_vingerafdruk: input.value.fingerprint,
  });
  if (error) {
    const mapped = signErrorResponse(error);
    return NextResponse.json({ error: mapped.error }, { status: mapped.status });
  }
  const status = data === "approved" || data === "locked" ? data : null;
  if (!status) {
    return NextResponse.json({ error: "Onverwacht antwoord van de database. Vernieuw de pagina." }, { status: 500 });
  }

  // De ondertekening staat vast; de logregels zijn administratie (een fout hierin draait niets terug).
  await supabase.from("domain_events").insert({
    restaurant_id: ctx.restaurantId,
    event_type: "ApprovalCompleted",
    payload: { receipt_id: params.id, method: "signature" },
    published_by: ctx.userId,
  });
  if (status === "locked") {
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
    action: "liet een bon ondertekenen door de klant",
    target_table: "receipts",
    target_id: params.id,
  });

  return NextResponse.json({ status, signedBy: input.value.name });
}
