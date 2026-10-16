import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { requireFeature } from "@/lib/features/feature-service";
import { getApprovalSettings, verifyApproval } from "@/lib/approval/approval-service";
import { getApprovalPin, ApprovalPinError, type ApprovalPin } from "@/lib/approval/approval-pin";
import { methodForReceipt, ADMIN_INCOMPLETE_WARNING, type ApprovalRule } from "@/lib/approval/approval-method";
import { startPinAttempt, finishPinAttempt, formatBlockedUntil, PinAttemptError } from "@/lib/approval/pin-attempts";
import { z } from "zod";

const approveSchema = z.object({
  credential: z.string().optional(), // PIN bij method=pin, leeg bij restaurant_confirms
});

const PIN_NIET_MOGELIJK = "PIN-controle is nu niet mogelijk, probeer het opnieuw";

export async function POST(
  request: Request,
  { params }: { params: { id: string } }
) {
  let ctx;
  try {
    ctx = await requireRole("APPROVE_RECEIPTS");
    await requireFeature("approval");
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

  // Methode per bon (stap 14a): de wachtende regel bepaalt de methode en het bedrijf; zonder regel de bedrijfsinstelling.
  // Dezelfde regel als de database (pin_eis) en het scherm (lib/approval/approval-method.ts). Leesfout = weigeren.
  const { data: rules, error: rulesError } = await supabase
    .from("approvals")
    .select("method, company_id, status")
    .eq("receipt_id", params.id)
    .eq("status", "pending");
  if (rulesError) {
    return NextResponse.json({ error: "Goedkeuringsregels konden niet worden gelezen, probeer het opnieuw" }, { status: 500 });
  }
  const pendingRules = (rules ?? []) as ApprovalRule[];
  const tabCompanyId: string | null = (receipt.open_tabs as any)?.company_id ?? null;
  const companyId = pendingRules[0]?.company_id ?? tabCompanyId;
  if (!companyId) {
    return NextResponse.json({ error: "Bon hoort niet bij een bedrijf" }, { status: 400 });
  }
  const settings = await getApprovalSettings(supabase, companyId);
  const forReceipt = methodForReceipt(pendingRules, tabCompanyId, settings.method);
  if (!forReceipt.ok) {
    return NextResponse.json({ error: forReceipt.reason }, { status: 409 });
  }
  const method = forReceipt.method;

  // Volgorde (stap 12 + 14a): rol -> bon via de gebruikerssessie (RLS) -> bedrijf van die bon -> poging reserveren
  // (telt meteen mee) -> pas dan de PIN-gegevens, alleen op de server. Elke fout: weigeren (fail closed).
  let pin: ApprovalPin | undefined;
  let attempt: { id: string; remaining: number; blockedUntil: string | null } | undefined;
  if (method === "pin") {
    if (!parsed.data.credential) {
      return NextResponse.json({ error: "PIN is verplicht" }, { status: 400 });
    }
    try {
      const start = await startPinAttempt(companyId, params.id);
      if (!start.allowed) {
        if (start.reason === "geblokkeerd") {
          const tot = formatBlockedUntil(start.blockedUntil);
          return NextResponse.json(
            { error: `Te veel onjuiste pogingen. PIN-goedkeuring voor dit bedrijf is geblokkeerd${tot ? ` tot ${tot}` : ""}.` },
            { status: 429 }
          );
        }
        return NextResponse.json({ error: "Deze bon wacht niet (meer) op een PIN-goedkeuring. Vernieuw de pagina." }, { status: 409 });
      }
      attempt = { id: start.id, remaining: start.remaining, blockedUntil: start.blockedUntil };
      pin = await getApprovalPin(companyId);
    } catch (err) {
      if (err instanceof PinAttemptError || err instanceof ApprovalPinError) {
        return NextResponse.json({ error: PIN_NIET_MOGELIJK }, { status: 500 });
      }
      throw err;
    }
  }

  const { data: userProfile } = await supabase
    .from("users")
    .select("full_name")
    .eq("id", ctx.userId)
    .single();

  // De Receipt Manager / deze route kent alleen de Approval Service — geen
  // kennis van PIN-hashing of providerdetails (klant-instructie, sectie 10.7).
  const result = await verifyApproval(
    { ...settings, method },
    { credential: parsed.data.credential, approverName: userProfile?.full_name ?? "Onbekend" },
    pin
  );

  if (attempt) {
    let finished;
    try {
      finished = await finishPinAttempt(attempt.id, result.success);
    } catch {
      return NextResponse.json({ error: PIN_NIET_MOGELIJK }, { status: 500 });
    }
    if (finished === "verlopen") {
      return NextResponse.json({ error: "De PIN is net gewijzigd. Probeer het opnieuw met de nieuwe PIN." }, { status: 409 });
    }
    if (finished !== "ok") {
      return NextResponse.json({ error: "Deze PIN-poging is al afgehandeld. Probeer het opnieuw." }, { status: 409 });
    }
    if (!result.success) {
      const tot = formatBlockedUntil(attempt.blockedUntil);
      const rest = attempt.remaining > 0
        ? `Nog ${attempt.remaining} ${attempt.remaining === 1 ? "poging" : "pogingen"}.`
        : `Te veel onjuiste pogingen: geblokkeerd${tot ? ` tot ${tot}` : ""}.`;
      return NextResponse.json({ error: `${result.reason ?? "Onjuiste PIN"}. ${rest}`, remaining: attempt.remaining }, { status: 400 });
    }
  }

  if (!result.success) {
    return NextResponse.json({ error: result.reason ?? "Goedkeuring mislukt" }, { status: 400 });
  }

  const newReceiptStatus = settings.autoLock ? "locked" : "approved";

  // Alleen een bon die nog wacht: een tweede (dubbel) verzoek werkt 0 rijen bij en krijgt een nette melding.
  const { data: updated, error: receiptUpdateError } = await supabase
    .from("receipts")
    .update({ status: newReceiptStatus })
    .eq("id", params.id)
    .eq("status", "pending_approval")
    .select("id");
  if (receiptUpdateError) {
    if (/PIN-goedkeuring ontbreekt of is verlopen/.test(receiptUpdateError.message)) {
      return NextResponse.json(
        { error: "De PIN-controle is verlopen of ontbreekt. Voer de PIN opnieuw in." },
        { status: 409 }
      );
    }
    return NextResponse.json({ error: receiptUpdateError.message }, { status: 500 });
  }
  if (!updated || updated.length === 0) {
    return NextResponse.json({ error: "Deze bon is al afgehandeld." }, { status: 409 });
  }

  // De bon IS nu goedgekeurd. Mislukt het bijwerken van de regel, dan geen foutmelding maar een waarschuwing:
  // de goedkeuring staat, alleen de administratie is niet volledig bijgewerkt (regel blijft pending, later bij te werken).
  const { error: ruleUpdateError } = await supabase
    .from("approvals")
    .update({
      status: "approved",
      approved_by: userProfile?.full_name ?? ctx.userId,
      approved_at: new Date().toISOString(),
    })
    .eq("receipt_id", params.id)
    .eq("status", "pending");
  const warning = ruleUpdateError ? ADMIN_INCOMPLETE_WARNING : null;

  await supabase.from("domain_events").insert({
    restaurant_id: ctx.restaurantId,
    event_type: "ApprovalCompleted",
    payload: { receipt_id: params.id, company_id: companyId, method },
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
    action: `keurde een bon goed (${method})`,
    target_table: "receipts",
    target_id: params.id,
  });

  return NextResponse.json({ status: newReceiptStatus, approvedBy: userProfile?.full_name ?? null, warning });
}
