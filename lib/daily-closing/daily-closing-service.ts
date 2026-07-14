import type { SupabaseClient } from "@supabase/supabase-js";

export interface DailyClosingReport {
  date: string;
  totalRevenue: number;
  businessRevenue: number;
  nonBusinessRevenue: number;
  invoicesToday: number;
  openBusinessTabs: number;
  awaitingInvoice: number;
  pendingApproval: number;
  draftReceipts: number;
  checks: {
    label: string;
    status: "ok" | "warning" | "not_applicable";
    detail?: string;
  }[];
  alreadyClosed: boolean;
  closedBy?: string | null;
  closedAt?: string | null;
}

/**
 * Verzamelt informatie uit andere modules — neemt nooit hun logica over,
 * alleen lezen uit de bestaande tabellen (governance 6.2: database is
 * bron van waarheid, geen dubbele state).
 */
export async function buildDailyClosingReport(
  supabase: SupabaseClient,
  restaurantId: string,
  date: string // YYYY-MM-DD
): Promise<DailyClosingReport> {
  const startOfDay = `${date}T00:00:00.000Z`;
  const endOfDay = `${date}T23:59:59.999Z`;

  const [
    { data: receiptsToday },
    { data: invoicesToday },
    { count: openBusinessTabs },
    { count: awaitingInvoice },
    { count: pendingApproval },
    { count: draftReceipts },
    { data: existingClosing },
  ] = await Promise.all([
    supabase
      .from("receipts")
      .select("total, open_tabs(company_id)")
      .eq("receipt_date", date)
      .not("status", "eq", "draft"),
    supabase.from("invoices").select("id").eq("issued_at", date),
    supabase
      .from("open_tabs")
      .select("id", { count: "exact", head: true })
      .eq("status", "open")
      .not("company_id", "is", null),
    supabase
      .from("open_tabs")
      .select("id", { count: "exact", head: true })
      .eq("status", "closed"),
    supabase
      .from("receipts")
      .select("id", { count: "exact", head: true })
      .eq("status", "pending_approval"),
    supabase
      .from("receipts")
      .select("id", { count: "exact", head: true })
      .eq("status", "draft"),
    supabase
      .from("daily_closings")
      .select("closed_at, users(full_name)")
      .eq("restaurant_id", restaurantId)
      .eq("closing_date", date)
      .maybeSingle(),
  ]);

  const totalRevenue = (receiptsToday ?? []).reduce((sum, r) => sum + Number(r.total ?? 0), 0);
  const businessRevenue = (receiptsToday ?? [])
    .filter((r: any) => r.open_tabs?.company_id)
    .reduce((sum, r) => sum + Number(r.total ?? 0), 0);
  const nonBusinessRevenue = totalRevenue - businessRevenue;

  const checks: DailyClosingReport["checks"] = [
    {
      label: "Geen open Approval-verzoeken",
      status: (pendingApproval ?? 0) === 0 ? "ok" : "warning",
      detail: (pendingApproval ?? 0) > 0 ? `${pendingApproval} bon(nen) wachten op goedkeuring` : undefined,
    },
    {
      label: "Geen open zakelijke rekeningen",
      status: (openBusinessTabs ?? 0) === 0 ? "ok" : "warning",
      detail: (openBusinessTabs ?? 0) > 0 ? `${openBusinessTabs} rekening(en) nog open` : undefined,
    },
    {
      label: "Geen openstaande conceptbonnen",
      status: (draftReceipts ?? 0) === 0 ? "ok" : "warning",
      detail: (draftReceipts ?? 0) > 0 ? `${draftReceipts} conceptbon(nen)` : undefined,
    },
    {
      label: "Afgekeurde bonnen",
      status: "not_applicable",
      detail: "Afkeuren bestaat nog niet in de Approval Engine — deze controle is nog niet mogelijk",
    },
    {
      label: "Niet-gekoppelde / ontbrekende bonnen",
      status: "not_applicable",
      detail: "Alleen relevant bij kassa-koppeling/import (Fase 2), nog niet gebouwd",
    },
    {
      label: "Contante / pin-omzetsplitsing",
      status: "not_applicable",
      detail: "Betaalmethode wordt nog niet per bon vastgelegd",
    },
  ];

  return {
    date,
    totalRevenue: Math.round(totalRevenue * 100) / 100,
    businessRevenue: Math.round(businessRevenue * 100) / 100,
    nonBusinessRevenue: Math.round(nonBusinessRevenue * 100) / 100,
    invoicesToday: invoicesToday?.length ?? 0,
    openBusinessTabs: openBusinessTabs ?? 0,
    awaitingInvoice: awaitingInvoice ?? 0,
    pendingApproval: pendingApproval ?? 0,
    draftReceipts: draftReceipts ?? 0,
    checks,
    alreadyClosed: !!existingClosing,
    closedBy: (existingClosing as any)?.users?.full_name ?? null,
    closedAt: existingClosing?.closed_at ?? null,
  };
}
