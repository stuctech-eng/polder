import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { z } from "zod";

const receiptLineSchema = z.object({
  description: z.string().min(1, "Omschrijving is verplicht"),
  quantity: z.number().positive(),
  unitPrice: z.number().nonnegative(),
  vatRate: z.number().nonnegative(),
});

const receiptSchema = z.object({
  receiptNumber: z.string().optional(),
  receiptDate: z.string().optional(),
  notes: z.string().optional(),
  lines: z.array(receiptLineSchema).min(1, "Minimaal één productregel is verplicht"),
});

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
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
  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Niet ingelogd" }, { status: 401 });
  }

  const body = await request.json();
  const parsed = receiptSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { data: profile } = await supabase
    .from("users")
    .select("restaurant_id")
    .eq("id", userData.user.id)
    .single();

  if (!profile) {
    return NextResponse.json({ error: "Geen restaurantprofiel gevonden" }, { status: 400 });
  }

  // Guardian Mode: tenant-isolatie — deze select is RLS-gefilterd op eigen restaurant,
  // dus als 'tab' hier null is, bestaat de rekening niet óf hoort die bij een ander
  // restaurant. Dit moet expliciet als fout behandeld worden, niet stilzwijgend
  // doorvallen naar "dus niet invoiced, dus toestaan" (dat was de eerdere bug-klasse).
  const { data: tab } = await supabase
    .from("open_tabs")
    .select("status")
    .eq("id", params.id)
    .single();

  if (!tab) {
    return NextResponse.json({ error: "Rekening niet gevonden" }, { status: 404 });
  }

  // Guardian Mode: impact-analyse — een gefactureerde rekening mag geen nieuwe bonnen
  // meer krijgen, anders klopt de al gegenereerde factuur niet meer met de werkelijkheid.
  if (tab.status === "invoiced") {
    return NextResponse.json(
      { error: "Deze rekening is al gefactureerd, er kunnen geen bonnen meer toegevoegd worden" },
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
      restaurant_id: profile.restaurant_id,
      open_tab_id: params.id,
      receipt_number: parsed.data.receiptNumber || null,
      source: "manual",
      status: "linked",
      subtotal,
      vat_amount: vatAmount,
      total,
      receipt_date: parsed.data.receiptDate || new Date().toISOString().slice(0, 10),
      notes: parsed.data.notes || null,
      created_by: userData.user.id,
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

  await supabase.from("activity_log").insert({
    restaurant_id: profile.restaurant_id,
    user_id: userData.user.id,
    action: `koppelde een bon (€${total.toFixed(2)}) aan een open rekening`,
    target_table: "receipts",
    target_id: receipt.id,
  });

  // Event Bus: ReceiptLinked (conform sectie 2 diagram)
  await supabase.from("domain_events").insert({
    restaurant_id: profile.restaurant_id,
    event_type: "ReceiptLinked",
    payload: { receipt_id: receipt.id, open_tab_id: params.id, total },
    published_by: userData.user.id,
  });

  return NextResponse.json({ receipt: { ...receipt, receipt_lines: linesWithTotals } }, { status: 201 });
}
