import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { generateInvoicePdf } from "@/lib/documents/invoice-pdf";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { invoiceBlockReason } from "@/lib/approval/invoice-blocking";

/**
 * Facturatie — genereert een factuur voor een gesloten open rekening.
 *
 * Guardian Mode (root cause / dependency / impact):
 * - Root cause: gebruiker wil een gesloten rekening afronden met een factuur.
 * - Dependency: rekening moet status 'closed' hebben en minimaal één bon bevatten.
 * - Impact: zet open_tab naar 'invoiced' (onomkeerbaar in Fase 1 — geen credit-flow nog).
 */
export async function POST(
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

  const supabase = createSupabaseServerClient();

  const { data: tab, error: tabError } = await supabase
    .from("open_tabs")
    .select("*, companies(name, address, vat_number, payment_term_days)")
    .eq("id", params.id)
    .single();

  if (tabError || !tab) {
    return NextResponse.json({ error: "Rekening niet gevonden" }, { status: 404 });
  }

  if (tab.status !== "closed") {
    return NextResponse.json(
      { error: "Alleen gesloten rekeningen kunnen gefactureerd worden" },
      { status: 400 }
    );
  }
  if (!tab.company_id) {
    return NextResponse.json(
      { error: "Rekening heeft geen bedrijf gekoppeld, kan niet factureren" },
      { status: 400 }
    );
  }

  const { data: receipts, error: receiptsError } = await supabase
    .from("receipts")
    .select("*")
    .eq("open_tab_id", params.id);

  if (receiptsError) {
    return NextResponse.json({ error: receiptsError.message }, { status: 500 });
  }
  if (!receipts || receipts.length === 0) {
    return NextResponse.json(
      { error: "Geen bonnen gekoppeld, kan geen factuur genereren" },
      { status: 400 }
    );
  }

  // Approval Engine-integratie: een bon die nog op goedkeuring wacht mag niet
  // meegenomen worden in een factuur — anders klopt de factuur niet meer
  // zodra de goedkeuring alsnog wordt afgewezen.
  //
  // Plan 7b: ook een afgewezen bon die nog niet opnieuw is ingediend en goedgekeurd mag niet
  // gefactureerd worden. Deze controle staat bewust VOOR het aanmaken van factuurnummer,
  // factuur, factuurregels, pdf en document: bij een blokkade ontstaat er niets.
  // De database (migratie 0023) weigert de overgang naar 'invoiced' daarnaast ook.
  // Alleen opvragen als er bonnen zijn: een .in()-filter zonder waarden mag het bestaande gedrag niet veranderen.
  // (Een rekening zonder bonnen wordt hierboven al afgehandeld met "Geen bonnen gekoppeld".)
  const receiptIds = receipts.map((r) => r.id);
  const { data: approvalRows, error: approvalsError } =
    receiptIds.length > 0
      ? await supabase.from("approvals").select("receipt_id, status").in("receipt_id", receiptIds)
      : { data: [] as { receipt_id: string; status: string }[], error: null };
  if (approvalsError) {
    // Fail closed: zonder goedkeuringsgegevens kunnen we de afwijzingsregel niet toetsen.
    return NextResponse.json(
      { error: "Goedkeuringsgegevens konden niet worden gecontroleerd — kan geen factuur genereren" },
      { status: 500 }
    );
  }
  const approvalsByReceipt = new Map<string, { status: string }[]>();
  for (const a of approvalRows ?? []) {
    const list = approvalsByReceipt.get(a.receipt_id) ?? [];
    list.push({ status: a.status });
    approvalsByReceipt.set(a.receipt_id, list);
  }
  const reasons = receipts.map((r) => ({
    receipt: r,
    reason: invoiceBlockReason(r, approvalsByReceipt.get(r.id) ?? []),
  }));
  if (reasons.some((x) => x.reason === "pending")) {
    return NextResponse.json(
      { error: "Eén of meer bonnen wachten nog op goedkeuring — kan geen factuur genereren" },
      { status: 400 }
    );
  }
  const rejectedReceipts = reasons.filter((x) => x.reason === "rejected").map((x) => x.receipt);
  if (rejectedReceipts.length > 0) {
    const names = rejectedReceipts
      .map((r) => (r.receipt_number ? `bon ${r.receipt_number}` : `bon zonder nummer (€${Number(r.total ?? 0).toFixed(2)})`))
      .join(", ");
    return NextResponse.json(
      {
        error:
          `Kan geen factuur genereren: ${names} is afgewezen en nog niet opnieuw goedgekeurd. ` +
          "Dien de bon opnieuw in en laat hem goedkeuren, of verwijder de bon.",
        blockedReceiptIds: rejectedReceipts.map((r) => r.id),
      },
      { status: 400 }
    );
  }

  const { data: restaurant } = await supabase
    .from("restaurants")
    .select("name")
    .eq("id", ctx.restaurantId)
    .single();

  const subtotal = Math.round(receipts.reduce((s, r) => s + Number(r.subtotal ?? 0), 0) * 100) / 100;
  const vatAmount = Math.round(receipts.reduce((s, r) => s + Number(r.vat_amount ?? 0), 0) * 100) / 100;
  const total = Math.round(receipts.reduce((s, r) => s + Number(r.total ?? 0), 0) * 100) / 100;

  // Factuurnummer: restaurant-scoped oplopend, per jaar (eenvoudig, uit te breiden)
  const year = new Date().getFullYear();
  const { count } = await supabase
    .from("invoices")
    .select("id", { count: "exact", head: true })
    .eq("restaurant_id", ctx.restaurantId);
  const invoiceNumber = `${year}-${String((count ?? 0) + 1).padStart(4, "0")}`;

  const issuedAt = new Date();
  const paymentTermDays = tab.companies?.payment_term_days ?? 30;
  const dueAt = new Date(issuedAt.getTime() + paymentTermDays * 24 * 60 * 60 * 1000);

  const { data: invoice, error: invoiceError } = await supabase
    .from("invoices")
    .insert({
      restaurant_id: ctx.restaurantId,
      company_id: tab.company_id,
      invoice_number: invoiceNumber,
      status: "draft",
      subtotal,
      vat_amount: vatAmount,
      total,
      issued_at: issuedAt.toISOString().slice(0, 10),
      due_at: dueAt.toISOString().slice(0, 10),
    })
    .select()
    .single();

  if (invoiceError) {
    return NextResponse.json({ error: invoiceError.message }, { status: 500 });
  }

  const invoiceLines = receipts.map((r) => ({
    invoice_id: invoice.id,
    receipt_id: r.id,
    description: r.receipt_number ? `Bon ${r.receipt_number}` : `Bon ${r.receipt_date ?? ""}`,
    amount: Number(r.total ?? 0),
  }));

  const { error: linesError } = await supabase.from("invoice_lines").insert(invoiceLines);
  if (linesError) {
    return NextResponse.json({ error: linesError.message }, { status: 500 });
  }

  // Document Engine: PDF genereren
  const pdfBytes = await generateInvoicePdf({
    invoiceNumber,
    issuedAt: issuedAt.toLocaleDateString("nl-NL"),
    dueAt: dueAt.toLocaleDateString("nl-NL"),
    restaurantName: restaurant?.name ?? "Restaurant",
    companyName: tab.companies?.name ?? "Onbekend bedrijf",
    companyAddress: tab.companies?.address,
    companyVatNumber: tab.companies?.vat_number,
    lines: invoiceLines.map((l) => ({ description: l.description, amount: l.amount })),
    subtotal,
    vatAmount,
    total,
  });

  // Security hardening stap 6 (H6): upsert:false — het pad bevat de nieuwe factuur-id, dus er is nooit een bestaand bestand;
  // bestanden in de bucket zijn onveranderlijk (geen UPDATE-policy meer), een bestaand bestand wordt nooit stilzwijgend vervangen.
  const storagePath = `${ctx.restaurantId}/invoices/${invoice.id}.pdf`;
  const { error: uploadError } = await supabase.storage
    .from("documents")
    .upload(storagePath, pdfBytes, { contentType: "application/pdf", upsert: false });

  if (uploadError) {
    // PDF-opslag mag falen zonder de hele factuur te blokkeren (sectie 15: fout zichtbaar,
    // niet de hele actie laten mislukken) — factuur staat er, PDF kan later opnieuw
    return NextResponse.json(
      {
        invoice,
        warning: `Factuur aangemaakt, maar PDF-opslag mislukte: ${uploadError.message}. Zorg dat de 'documents' storage bucket bestaat in Supabase.`,
      },
      { status: 201 }
    );
  }

  await supabase.from("documents").insert({
    restaurant_id: ctx.restaurantId,
    type: "invoice",
    related_table: "invoices",
    related_id: invoice.id,
    storage_path: storagePath,
  });

  await supabase
    .from("open_tabs")
    .update({ status: "invoiced" })
    .eq("id", params.id);

  await supabase.from("activity_log").insert({
    restaurant_id: ctx.restaurantId,
    user_id: ctx.userId,
    action: `genereerde factuur ${invoiceNumber} (€${total.toFixed(2)})`,
    target_table: "invoices",
    target_id: invoice.id,
  });

  // Event Bus: InvoiceGenerated
  await supabase.from("domain_events").insert({
    restaurant_id: ctx.restaurantId,
    event_type: "InvoiceGenerated",
    payload: { invoice_id: invoice.id, open_tab_id: params.id, total },
    published_by: ctx.userId,
  });

  return NextResponse.json({ invoice }, { status: 201 });
}
