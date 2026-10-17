// Stap 14c: het ECHTE scherm (ReceiptsSection + SignatureDialog) met echte React in jsdom. Geen database: fetch is nagebootst.
// Bouwen: node build22.js <repo>; draaien: NODE_PATH=<map met jsdom>/node_modules node t22.js
import "./stubs/dom-setup";
import * as React from "react";
import { createRoot } from "react-dom/client";
const { act } = React as any;
import { ReceiptsSection } from "@/app/(dashboard)/open-tabs/[id]/receipts-section";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const g = globalThis as any; const w = g.window;
const SIG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAASwAAAB4CAAAAABtfpD8AAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC"; // echte PNG 300x120
const FP = "0123456789abcdef0123456789abcdef";
// canvas bestaat in jsdom niet echt: een nep-tekencontext die vastlegt dat er getekend is, en een vaste PNG
let strepen = 0;
w.HTMLCanvasElement.prototype.getContext = function () {
  return { scale() {}, beginPath() {}, moveTo() {}, lineTo() {}, stroke() { strepen++; }, save() {}, restore() {}, setTransform() {}, clearRect() {},
    set lineWidth(_: any) {}, set lineCap(_: any) {}, set lineJoin(_: any) {}, set strokeStyle(_: any) {} };
};
w.HTMLCanvasElement.prototype.toDataURL = () => SIG;
let calls: { url: string; body: any }[] = []; let antwoord: () => Promise<any> = async () => ({ ok: true, status: 200, json: async () => ({}) });
g.fetch = w.fetch = async (url: string, init: any) => { calls.push({ url, body: JSON.parse(init?.body ?? "null") }); return antwoord(); };
const bon = (extra: any = {}) => ({ id: "b1", receipt_number: "T-1", status: "pending_approval", total: 12.5, subtotal: 12.5, vat_amount: 0, receipt_date: "2026-10-16",
  receipt_lines: [{ description: "Lunch", quantity: 1, unit_price: 11.47, line_total: 12.5 }], approval_method: "signature", signature_fingerprint: FP, ...extra });

(async () => {
  const root = createRoot(document.getElementById("root")!);
  const toon = async (bonnen: any[], signatureEnabled = true) => {
    await act(async () => { root.render(React.createElement(ReceiptsSection, { openTabId: "t1", initialReceipts: bonnen, isInvoiced: false, canAddReceipts: true,
      approvalMethod: "signature", approvalEnabled: true, signatureEnabled, companyName: "Teken BV" })); });
  };
  const tekst = () => document.body.textContent ?? "";
  const knop = (t: string) => [...document.querySelectorAll("button")].find((b) => (b.textContent ?? "").includes(t)) as HTMLButtonElement | undefined;
  const klik = async (t: string) => { await act(async () => { knop(t)!.dispatchEvent(new w.MouseEvent("click", { bubbles: true })); }); };
  const dialoog = () => document.querySelector("[role=dialog]");
  const typ = async (waarde: string) => { const el = dialoog()!.querySelector("input") as HTMLInputElement;
    const setter = Object.getOwnPropertyDescriptor(w.HTMLInputElement.prototype, "value")!.set!;
    await act(async () => { setter.call(el, waarde); el.dispatchEvent(new w.Event("input", { bubbles: true })); }); };
  const teken = async () => { const c = dialoog()!.querySelector("canvas")!;
    for (const [t, x] of [["pointerdown", 10], ["pointermove", 40], ["pointermove", 80], ["pointerup", 80]] as [string, number][])
      await act(async () => { c.dispatchEvent(new w.MouseEvent(t, { bubbles: true, clientX: x, clientY: 20 })); }); };

  await toon([bon()], false);
  ok("1 module Handtekening uit: melding, geen knop om te tekenen; belooft geen afwijzen in de app", /module Handtekening staat uit/.test(tekst()) && !knop("Laten tekenen")
     && /Afwijzen kan in de app niet/.test(tekst()) && /platformbeheerder de module aanzet/.test(tekst()) && !/wijs de bon af/.test(tekst()), tekst().slice(0, 300));
  await toon([bon({ signature_fingerprint: null })]);
  ok("2 geen vingerafdruk van de server: melding 'vernieuw', geen knop", /Vernieuw de pagina/.test(tekst()) && !knop("Laten tekenen"), tekst().slice(0, 300));
  await toon([bon()]);
  ok("3 handtekeningbon: knop 'Laten tekenen door de klant', geen gewone Goedkeuren-knop of PIN-veld", !!knop("Laten tekenen") && !knop("Goedkeuren") && !document.querySelector("input[type=password]"));
  await klik("Laten tekenen");
  ok("4 tekenscherm open: bedrijf, bon, regel en totaal zichtbaar; Bevestigen uit", !!dialoog() && /Teken BV/.test(dialoog()!.textContent!) && /voor Teken BV/.test(dialoog()!.textContent!) && /T-1/.test(dialoog()!.textContent!) && /Lunch/.test(dialoog()!.textContent!)
     && /€12\.50/.test(dialoog()!.textContent!) && knop("Bevestigen")!.disabled, dialoog()?.textContent?.slice(0, 200));
  await typ("  Jan  ");
  ok("5 alleen naam ingevuld: Bevestigen nog uit (eerst tekenen)", knop("Bevestigen")!.disabled);
  strepen = 0; await teken();
  ok("6 getekend: streep gezet en Bevestigen aan", strepen > 0 && !knop("Bevestigen")!.disabled, String(strepen));
  await klik("Wissen");
  ok("7 Wissen: Bevestigen weer uit", knop("Bevestigen")!.disabled);
  await teken();
  antwoord = async () => ({ ok: false, status: 409, json: async () => ({ error: "De bon is intussen gewijzigd. Vernieuw de pagina en laat de klant opnieuw tekenen." }) });
  calls = []; await klik("Bevestigen");
  ok("8 server weigert: melding in het tekenscherm, scherm blijft open, bon wacht nog", !!dialoog() && /intussen gewijzigd/.test(dialoog()!.textContent!) && /wacht op goedkeuring/.test(tekst()), tekst().slice(0, 300));
  ok("9 verzoek: juiste route, naam zonder spaties, handtekening en vingerafdruk van de server", calls.length === 1 && calls[0].url === "/api/receipts/b1/sign"
     && calls[0].body.name === "Jan" && calls[0].body.signature === SIG && calls[0].body.fingerprint === FP, JSON.stringify(calls).slice(0, 200));
  antwoord = async () => { throw new Error("netwerk"); };
  await klik("Bevestigen");
  ok("10 geen verbinding: duidelijke melding, niet ondertekend", /Geen verbinding/.test(dialoog()?.textContent ?? ""), dialoog()?.textContent?.slice(0, 200));
  calls = []; await klik("Annuleren");
  ok("11 Annuleren: scherm dicht, geen verzoek, bon wacht nog", !dialoog() && calls.length === 0 && /wacht op goedkeuring/.test(tekst()));
  await klik("Laten tekenen"); await typ("Jan Klant"); await teken();
  // tekenvlak levert geen echte PNG: niet versturen
  w.HTMLCanvasElement.prototype.toDataURL = () => "data:image/png;base64," + "A".repeat(300);
  calls = []; await klik("Bevestigen");
  ok("12a tekenvlak geeft geen echte PNG: melding, niets verstuurd", calls.length === 0 && /niet worden vastgelegd/.test(dialoog()?.textContent ?? ""), dialoog()?.textContent?.slice(0, 200));
  w.HTMLCanvasElement.prototype.toDataURL = () => SIG;
  antwoord = async () => ({ ok: true, status: 200, json: async () => ({ status: "locked", signedBy: "Jan Klant" }) });
  g.__refreshes = 0; await klik("Bevestigen");
  ok("12 gelukt: scherm dicht, bon 'getekend door Jan Klant', pagina ververst", !dialoog() && /getekend door Jan Klant/.test(tekst()) && !/wacht op goedkeuring/.test(tekst()) && g.__refreshes === 1,
     tekst().slice(0, 300) + " refresh=" + g.__refreshes);
  await toon([bon({ id: "b2", approval_method: "pin", signature_fingerprint: undefined })]);
  ok("13 PIN-bon ongewijzigd: PIN-veld en Goedkeuren, geen tekenknop", !!document.querySelector("input[type=password]") && !!knop("Goedkeuren") && !knop("Laten tekenen"));
  await toon([bon({ id: "b3", status: "locked", approved_by: "Piet", approved_method: "pin" })]);
  ok("14 bon goedgekeurd met PIN: 'goedgekeurd door Piet' (niet 'getekend')", /goedgekeurd door Piet/.test(tekst()) && !/getekend/.test(tekst()), tekst().slice(0, 200));

  await act(async () => { root.unmount(); });
  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  process.exit(fail ? 1 : 0);
})().catch((err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
