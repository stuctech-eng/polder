import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getApprovalSettings, notifyApprovalRequested, submitForApproval } from "@/lib/approval/approval-service";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { isFeatureOn } from "@/lib/features/feature-service";
import { z } from "zod";

const receiptLineSchema = z.object({
  description: z.string().trim().min(1, "vul een omschrijving in"),
  quantity: z.number({ invalid_type_error: "het aantal is geen getal" }).positive("het aantal moet groter zijn dan 0"),
  unitPrice: z.number({ invalid_type_error: "de prijs is geen getal" }).nonnegative("de prijs mag niet negatief zijn"),
  vatRate: z.number({ invalid_type_error: "het btw-percentage is geen getal" }).nonnegative("het btw-percentage mag niet negatief zijn"),
});

const receiptSchema = z.object({
  receiptNumber: z.string().optional(),
  receiptDate: z.string().optional(),
  notes: z.string().optional(),
  lines: z.array(receiptLineSchema).min(1, "Voeg minstens één productregel toe."),
});

/** Leesbare melding voor de gebruiker: de eerste fout, bij een productregel met het regelnummer (16 okt: was "Validatiefout"). */
function validationMessage(error: z.ZodError): string {
  const issue = error.issues[0];
  if (!issue) return "De bon is niet volledig ingevuld.";
  const [field, index] = issue.path;
  if (field === "lines" && typeof index === "number") return `Productregel ${index + 1}: ${issue.message}.`;
  return issue.message;
}

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    await requireRole("MANAGE_RECEIPTS");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();
  const { data, error } = await supabase
    .from("receipts")
    .select("*, receipt_lines(*)")
    .eq("open_tab_id", params.id)
    .order("created_at", { ascending: false });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({ receipts: data });
}

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

  const body = await request.json();
  const parsed = receiptSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: validationMessage(parsed.error), details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  // Guardian Mode: tenant-isolatie — deze select is RLS-gefilterd op eigen restaurant,
  // dus als 'tab' hier null is, bestaat de rekening niet óf hoort die bij een ander
  // restaurant. Dit moet expliciet als fout behandeld worden, niet stilzwijgend
  // doorvallen naar "dus niet invoiced, dus toestaan" (dat was de eerdere bug-klasse).
  const { data: tab } = await supabase
    .from("open_tabs")
    .select("status, company_id")
    .eq("id", params.id)
    .single();

  if (!tab) {
    return NextResponse.json({ error: "Rekening niet gevonden" }, { status: 404 });
  }

  // Guardian Mode: impact-analyse — zodra een rekening gesloten is, komt de gast niet
  // meer terug voor extra bestellingen. Alleen een OPEN rekening mag nieuwe bonnen
  // krijgen — "closed" en "invoiced" zijn beide eindstadia voor nieuwe bonnen.
  if (tab.status !== "open") {
    return NextResponse.json(
      {
        error:
          tab.status === "invoiced"
            ? "Deze rekening is al gefactureerd, er kunnen geen bonnen meer toegevoegd worden"
            : "Deze rekening is gesloten, er kunnen geen bonnen meer toegevoegd worden",
      },
      { status: 400 }
    );
  }

  // Receipt Validation: totalen berekenen uit de regels (sectie Receipt Engine)
  let subtotal = 0;
  let vatAmount = 0;
  const linesWithTotals = parsed.data.lines.map((line) => {
    const lineSubtotal = line.quantity * line.unitPrice;
    const lineVat = lineSubtotal * (line.vatRate / 100);
    subtotal += lineSubtotal;
    vatAmount += lineVat;
    return {
      description: line.description,
      quantity: line.quantity,
      unit_price: line.unitPrice,
      vat_rate: line.vatRate,
      line_total: Math.round((lineSubtotal + lineVat) * 100) / 100,
    };
  });
  subtotal = Math.round(subtotal * 100) / 100;
  vatAmount = Math.round(vatAmount * 100) / 100;
  const total = Math.round((subtotal + vatAmount) * 100) / 100;

  // Receipt Manager: bon aanmaken, direct gekoppeld (Receipt Linking) want handmatig
  // ingevoerd op een specifieke open rekening
  const { data: receipt, error: receiptError } = await supabase
    .from("receipts")
    .insert({
      restaurant_id: ctx.restaurantId,
      open_tab_id: params.id,
      receipt_number: parsed.data.receiptNumber || null,
      source: "manual",
      status: "linked",
      subtotal,
      vat_amount: vatAmount,
      total,
      receipt_date: parsed.data.receiptDate || new Date().toISOString().slice(0, 10),
      notes: parsed.data.notes || null,
      created_by: ctx.userId,
    })
    .select()
    .single();

  if (receiptError) {
    return NextResponse.json({ error: receiptError.message }, { status: 500 });
  }

  const { error: linesError } = await supabase
    .from("receipt_lines")
    .insert(linesWithTotals.map((line) => ({ ...line, receipt_id: receipt.id })));

  if (linesError) {
    return NextResponse.json({ error: linesError.message }, { status: 500 });
  }

  // Approval Engine-integratie: de Receipt Manager weet alleen "dit bedrijf
  // vereist goedkeuring" — geen kennis van PIN/restaurant_confirms/e-mail/QR
  // zelf (klant-instructie, sectie 10.7).
  let finalStatus = receipt.status;
  let approvalToken: string | null = null;
  let approvalWarning: string | null = null;
  if (tab.company_id) {
    const settings = await getApprovalSettings(supabase, tab.company_id);
    if (settings.enabled && settings.method) {
      // Indienen in een keer (bon + regel, methode uit de bedrijfsinstelling; migratie 0041). Lukt het niet, dan blijft
      // de bon gekoppeld (niet wachtend) en ziet de gebruiker waarom: nooit een wachtende bon zonder goedkeuringsregel.
      const submitted = await submitForApproval(supabase, receipt.id);
      if (!submitted.ok) {
        approvalWarning = submitted.settingChanged
          ? "Goedkeuring is niet aangevraagd: de goedkeuringsinstelling van dit bedrijf is net gewijzigd. Dien de bon opnieuw in."
          : `Goedkeuring is niet aangevraagd: ${submitted.error}. Dien de bon opnieuw in.`;
      } else if (submitted.method) {
        const method = submitted.method;
        finalStatus = "pending_approval";
        approvalToken = submitted.approvalToken;

        // Keuze A (fase 4): staat de module Goedkeuring uit, dan wacht de bon wel, maar gaat er geen mail uit.
        if (method === "email" && (await isFeatureOn("approval"))) {
          const { data: restaurant } = await supabase
            .from("restaurants")
            .select("name")
            .eq("id", ctx.restaurantId)
            .single();
          const notifyResult = await notifyApprovalRequested({
            settings: { ...settings, method },
            token: approvalToken!,
            restaurantName: restaurant?.name ?? "Restaurant",
            receiptTotal: total,
            baseUrl: process.env.NEXT_PUBLIC_SITE_URL || "https://polder.vercel.app",
          });
          if (!notifyResult.success) {
            approvalWarning = notifyResult.warning ?? "Kon goedkeuringsmail niet versturen";
          }
        }

        await supabase.from("domain_events").insert({
          restaurant_id: ctx.restaurantId,
          event_type: "ApprovalRequested",
          payload: { receipt_id: receipt.id, company_id: tab.company_id, method },
          published_by: ctx.userId,
        });
      }
    }
  }

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `koppelde een bon (€${total.toFixed(2)}) aan een open rekening`,
    target_table: "receipts",
    target_id: receipt.id,
  });

  // Event Bus: ReceiptLinked (conform sectie 2 diagram)
  await supabase.from("domain_events").insert({
    restaurant_id: ctx.restaurantId,
    event_type: "ReceiptLinked",
    payload: { receipt_id: receipt.id, open_tab_id: params.id, total },
    published_by: ctx.userId,
  });

  return NextResponse.json(
    {
      receipt: { ...receipt, status: finalStatus, receipt_lines: linesWithTotals },
      approvalToken,
      approvalWarning,
    },
    { status: 201 }
  );
}
