// Rekeningpagina ververst zichzelf (16 okt 2026): regel needsAutoRefresh + het echte scherm (ReceiptsSection) in jsdom.
// Geen database. Bouwen: node build18.js <repo>; draaien: NODE_PATH=<map met jsdom>/node_modules node t18.js
import "./stubs/dom-setup";
import * as React from "react";
import { createRoot } from "react-dom/client";
const { act } = React as any;
import { ReceiptsSection } from "@/app/(dashboard)/open-tabs/[id]/receipts-section";
import { needsAutoRefresh, AUTO_REFRESH_MS } from "@/lib/approval/auto-refresh";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const g = globalThis as any;
const bon = (id: string, status: string, approval_method?: any, extra: any = {}) => ({ id, receipt_number: "B-" + id, status, total: 5, subtotal: 5, vat_amount: 0,
  receipt_date: "2026-10-16", receipt_lines: [], approval_token: approval_method === "qr" ? "tok-" + id : null, approval_method, ...extra });

(async () => {
  // ===== 1. de regel
  ok("1 wachtende QR-bon: verversen", needsAutoRefresh([bon("1", "pending_approval", "qr")], true, null));
  ok("2 wachtende e-mailbon: verversen", needsAutoRefresh([bon("1", "pending_approval", "email")], true, null));
  ok("3 wachtende PIN- of restaurant_confirms-bon: niet", !needsAutoRefresh([bon("1", "pending_approval", "pin"), bon("2", "pending_approval", "restaurant_confirms")], true, "qr"));
  ok("4 module Goedkeuring uit: niet", !needsAutoRefresh([bon("1", "pending_approval", "qr")], false, "qr"));
  ok("5 niets wacht (QR-bon al goedgekeurd): niet", !needsAutoRefresh([bon("1", "locked", "qr"), bon("2", "linked", "qr")], true, "qr"));
  ok("6 net aangemaakte bon zonder eigen methode: bedrijfsinstelling telt (qr = ja, pin = nee)",
     needsAutoRefresh([bon("1", "pending_approval", undefined)], true, "qr") && !needsAutoRefresh([bon("1", "pending_approval", undefined)], true, "pin"));
  ok("7 tegenstrijdige regels (geen knop, geen link): niet", !needsAutoRefresh([bon("1", "pending_approval", null, { approval_conflict: "x" })], true, "qr"));

  // ===== 2. het echte scherm
  const root = createRoot(document.getElementById("root")!);
  const toon = async (bonnen: any[], aan = true, methode: any = "qr") => {
    await act(async () => { root.render(React.createElement(ReceiptsSection, { openTabId: "t1", initialReceipts: bonnen, isInvoiced: false, canAddReceipts: true, approvalMethod: methode, approvalEnabled: aan })); });
  };
  const timers = () => [...g.__timers.values()] as { fn: () => void; ms: number }[];
  const tekst = () => document.body.textContent ?? "";

  await toon([bon("1", "pending_approval", "qr"), bon("2", "locked", "pin")]);
  ok("8 scherm met wachtende QR-bon: precies 1 timer van 5 seconden", timers().length === 1 && timers()[0].ms === AUTO_REFRESH_MS && AUTO_REFRESH_MS === 5000, JSON.stringify(timers().map((t) => t.ms)));
  g.__refreshes = 0; await act(async () => { timers()[0]?.fn(); });
  ok("9 timer loopt af terwijl de app zichtbaar is: 1 keer verversen", g.__refreshes === 1, String(g.__refreshes));
  await act(async () => { g.__setVisible(false); });
  g.__refreshes = 0; await act(async () => { timers()[0]?.fn(); });
  ok("10 app op de achtergrond: timer ververst niet", g.__refreshes === 0, String(g.__refreshes));
  await act(async () => { g.__setVisible(true); });
  ok("11 terug in de app: meteen 1 keer verversen", g.__refreshes === 1, String(g.__refreshes));
  ok("12 vooraf: bon 1 toont 'wacht op goedkeuring' en de QR-link", /wacht op goedkeuring/.test(tekst()) && /Scan om goed te keuren/.test(tekst()), tekst().slice(0, 200));
  // server geeft na verversen nieuwe gegevens: bon 1 is goedgekeurd via de link
  await toon([bon("1", "locked", "qr", { approved_by: "Eten" }), bon("2", "locked", "pin")]);
  ok("13 nieuwe gegevens van de server worden overgenomen: bon 1 'goedgekeurd door Eten', geen QR-link meer",
     /goedgekeurd door Eten/.test(tekst()) && !/Scan om goed te keuren/.test(tekst()), tekst().slice(0, 300));
  ok("14 niets wacht meer: timer gestopt", timers().length === 0, String(timers().length));
  g.__refreshes = 0; await act(async () => { g.__setVisible(true); });
  ok("15 ... en terug in de app ververst ook niet meer", g.__refreshes === 0, String(g.__refreshes));

  // waarschuwing "administratie niet volledig": komt van de server en blijft staan zolang de server hem meegeeft
  const W = "Goedgekeurd, maar de administratie is nog niet volledig bijgewerkt (goedkeuringsregel). Meld dit aan een beheerder.";
  await toon([bon("6", "locked", "pin", { approval_warning: W }), bon("7", "pending_approval", "qr")]);
  await act(async () => { timers()[0]?.fn(); });
  await toon([bon("6", "locked", "pin", { approval_warning: W }), bon("7", "pending_approval", "qr")]);
  ok("15b waarschuwing blijft staan na verversen zolang de server hem meegeeft", tekst().includes(W), tekst().slice(0, 300));
  await toon([bon("6", "locked", "pin", { approval_warning: null }), bon("7", "pending_approval", "qr")]);
  ok("15c pas als de server meldt dat het opgelost is, verdwijnt de waarschuwing", !tekst().includes(W), tekst().slice(0, 300));

  await toon([bon("3", "pending_approval", "pin")], true, "pin");
  ok("16 alleen een wachtende PIN-bon: geen timer", timers().length === 0, String(timers().length));
  await toon([bon("4", "pending_approval", "qr")], false, "qr");
  ok("17 module Goedkeuring uit: geen timer", timers().length === 0, String(timers().length));
  await toon([bon("5", "pending_approval", "email")], true, "pin");
  ok("18 wachtende e-mailbon bij een PIN-bedrijf (methode per bon): wel een timer", timers().length === 1, String(timers().length));
  // stap 14b: bon nog niet ingediend bij een bedrijf dat goedkeuring vereist -> melding en knop "Indienen"
  const knoppen = () => [...document.querySelectorAll("button")].map((b) => b.textContent ?? "");
  await toon([bon("8", "linked", "pin", { submission_needed: true }), bon("9", "linked", "pin", { rejection_blocked: true })], true, "pin");
  ok("21 bon nog niet ingediend: melding 'Nog niet ingediend' en knop 'Indienen'; afgewezen bon houdt 'Opnieuw indienen'",
     /Nog niet ingediend: dit bedrijf vereist goedkeuring/.test(tekst()) && knoppen().includes("Indienen") && knoppen().includes("Opnieuw indienen"), JSON.stringify(knoppen()));
  await toon([bon("8", "linked", "pin", { submission_needed: true })], false, "pin");
  ok("22 module Goedkeuring uit: geen knop 'Indienen'", !knoppen().includes("Indienen"), JSON.stringify(knoppen()));
  await toon([bon("8", "linked", "pin", { submission_needed: false })], true, "pin");
  ok("23 bedrijf zonder verplichting: geen melding en geen knop", !/Nog niet ingediend/.test(tekst()) && !knoppen().includes("Indienen"), JSON.stringify(knoppen()));
  await act(async () => { root.unmount(); });
  ok("19 pagina verlaten: timer opgeruimd", timers().length === 0, String(timers().length));
  g.__refreshes = 0; await act(async () => { g.__setVisible(false); g.__setVisible(true); });
  ok("20 pagina verlaten: ook de luisteraar is weg (terugkomen in de app ververst niet meer)", g.__refreshes === 0, String(g.__refreshes));

  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  process.exit(fail ? 1 : 0);
})().catch((err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
