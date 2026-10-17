// Stap 14c: handtekening van de klant. ECHTE routes en pagina; database MET 0043-0048 (bon_ondertekenen, wachten).
// Bouwen: node build21.js <repo>; draaien: PGHOST=… PGPORT=… PGUSER=… TESTDB=… NODE_PATH=… node t21.js
import * as sign from "@/app/api/receipts/[id]/sign/route";
import * as approve from "@/app/api/receipts/[id]/approve/route";
import * as settingsRoute from "@/app/api/companies/[id]/approval-settings/route";
import * as reqApproval from "@/app/api/receipts/[id]/request-approval/route";
import OpenTabDetailPage from "@/app/(dashboard)/open-tabs/[id]/page";
import { checkSignatureInput, signErrorResponse, isValidSignaturePng, COMPANY_MISMATCH } from "@/lib/approval/signature";
import { needsAutoRefresh } from "@/lib/approval/auto-refresh";
import { FEATURES, isFeatureKey } from "@/lib/features/features";
// @ts-ignore
import { cfg, end } from "@supabase/supabase-js";
import { Client } from "pg";
process.env.SUPABASE_SERVICE_ROLE_KEY = "service"; process.env.NEXT_PUBLIC_SUPABASE_URL = "x"; process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "anon";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const RA = "a0000000-0000-0000-0000-000000000001";
const A = (n: number) => `a0000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
// echte PNG's (gemaakt met dezelfde generator als handtekening-tests.sh), plus kapotte varianten
const PNG = {
  P300: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAASwAAAB4CAAAAABtfpD8AAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC",
  P2048: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAACAAAAAQACAAAAABQbOaYAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC",
  P1: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC",
  ZONDER_IEND: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAAAAACoWZBhAAAA1XRFWHR4AHl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXlFcAduAAAADElEQVR4nGNgYGAAAAAEAAH2FzhV",
  IHDR_KAPOT: "data:image/png;base64,iVBORw0KGgoAAAANSUhEWAAAAAoAAAAKCAAAAAB6bkr6AAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC",
  W2049: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAACAEAAAAKCAAAAADqeorTAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC",
  H1025: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAoAAAQBCAAAAAA20USxAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC",
  GEEN_PNG: "data:image/png;base64,aGFsbG8gd2VyZWxkLCBkaXQgaXMgZ2VlbiBwbGFhdGplIGhhbGxvIHdlcmVsZCwgZGl0IGlzIGdlZW4gcGxhYXRqZSBoYWxsbyB3ZXJlbGQsIGRpdCBpcyBnZWVuIHBsYWF0amUgaGFsbG8gd2VyZWxkLCBkaXQgaXMgZ2VlbiBwbGFhdGplIGhhbGxvIHdlcmVsZCwgZGl0IGlzIGdlZW4gcGxhYXRqZSA=",
};
const SIG = PNG.P300;
function walk(el: any, f: (e: any) => void) {
  if (el == null || typeof el !== "object") return;
  if (Array.isArray(el)) return el.forEach((x) => walk(x, f));
  f(el); walk(el.props?.children, f);
}
(async () => {
  const q = new Client({ host: process.env.PGHOST, port: +(process.env.PGPORT || 55432), database: process.env.TESTDB, user: process.env.PGUSER });
  await q.connect();
  const one = async (sql: string, p: any[] = []) => (await q.query(sql, p)).rows[0] ?? {};
  const uid = async (e: string) => (await one("select id from auth.users where email=$1", [e])).id;
  const U: any = { owner: { id: await uid("a.owner@staging.test") }, mgr: { id: await uid("a.manager@staging.test") },
    bed: { id: await uid("a.bediening@staging.test") }, keuken: { id: await uid("a.keuken@staging.test") } };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const req = (method: string, body?: any) => new Request("http://x/", { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const res = async (r: Response) => ({ status: r.status, json: await r.json().catch(() => ({})) });
  const status = async (id: string) => (await one("select status from receipts where id=$1", [id])).status;
  const regel = async (id: string) => one("select status, approved_by, signature_data, method from approvals where receipt_id=$1 order by created_at desc limit 1", [id]);
  const vinger = async (id: string) => (await one("select public.bon_vingerafdruk($1) v", [id])).v as string;
  const teken = async (id: string, body: any) => res(await sign.POST(req("POST", body), { params: { id } }));
  const module = async (aan: boolean) => { await q.query("delete from restaurant_features where restaurant_id=$1 and feature='signature'", [RA]);
    if (aan) await q.query("insert into restaurant_features values ($1,'signature',true,now())", [RA]); };

  // ===== 1. invoer en meldingen (zonder database)
  ok("1 geldige invoer: naam zonder spaties eromheen", (() => { const c = checkSignatureInput({ name: "  Jan  ", signature: SIG, fingerprint: "a".repeat(32) }); return c.ok && c.value.name === "Jan"; })());
  ok("2 naam te kort / te lang / ontbreekt: Nederlandse melding", ["J", "x".repeat(101), undefined, "   "].every((n) => { const c = checkSignatureInput({ name: n, signature: SIG, fingerprint: "a".repeat(32) }); return !c.ok && /naam van de klant/.test(c.error); }));
  const slecht: [string, string][] = [["ongeldige base64 (201 x A)", "data:image/png;base64," + "A".repeat(201)], ["base64 zonder PNG", PNG.GEEN_PNG],
    ["PNG zonder IEND", PNG.ZONDER_IEND], ["eerste blok geen IHDR", PNG.IHDR_KAPOT], ["breedte 2049", PNG.W2049], ["hoogte 1025", PNG.H1025],
    ["jpeg-voorvoegsel", SIG.replace("image/png", "image/jpeg")], ["witruimte", SIG.slice(0, 60) + " " + SIG.slice(60)], ["vreemd teken", SIG + "<"],
    ["te lang (200022 tekens)", "data:image/png;base64," + "A".repeat(200000)]];
  const fout = slecht.filter(([, v]) => isValidSignaturePng(v) || checkSignatureInput({ name: "Jan", signature: v, fingerprint: "a".repeat(32) }).ok).map(([n]) => n);
  ok("3 geen echte PNG (ongeldige base64, geen PNG, zonder IEND, geen IHDR, te breed, te hoog, jpeg, witruimte, te lang): geweigerd", fout.length === 0, fout.join(", "));
  ok("3b echte PNG's 300x120, 2048x1024 (grens) en 1x1: geldig", [PNG.P300, PNG.P2048, PNG.P1].every((v) => isValidSignaturePng(v)));
  ok("4 vingerafdruk ontbreekt of verkeerd formaat: melding 'vernieuw'", [undefined, "x", "A".repeat(32)].every((f) => { const c = checkSignatureInput({ name: "Jan", signature: SIG, fingerprint: f }); return !c.ok && /Vernieuw/.test(c.error); }));
  const m = (code: string, message = "") => signErrorResponse({ code, message });
  ok("5 databasefouten -> status en melding", m("P0002").status === 404 && m("42501", "Module staat uit").status === 403 && /module Handtekening/.test(m("42501", "Module staat uit").error)
     && /geen recht/.test(m("42501", "Geen recht").error) && m("55000").status === 409 && /wacht niet/.test(m("55000").error)
     && m("22000").status === 409 && /gewijzigd/.test(m("22000").error) && m("22000", "Bedrijf verschilt").error === COMPANY_MISMATCH
     && !/afwijzen/i.test(COMPANY_MISMATCH) && /beheerder/.test(COMPANY_MISMATCH) && m("55000", "Regel gewijzigd").status === 409 && m("22023", "Naam: 2 tot 100 tekens").status === 400 && /naam/.test(m("22023", "Naam").error)
     && m("XX000").status === 500 && /niet gewijzigd/.test(m("XX000").error));
  ok("6 module in de lijst (platformbeheer), na Goedkeuring", isFeatureKey("signature") && FEATURES.map((f) => f.key).join(",") === "daily_closing,payment_registration,approval,signature");
  ok("7 automatisch verversen: niet voor een handtekeningbon (tekenen gebeurt op dit scherm)", !needsAutoRefresh([{ status: "pending_approval", approval_method: "signature" }], true, null)
     && !needsAutoRefresh([{ status: "pending_approval" }], true, "signature"));

  // ===== opzet: bedrijf TEKEN (methode signature, verplicht), rekening met bon die wacht op een handtekening
  const TEKEN = A(9710), TAB = A(9711), BON = A(9712), TAB2 = A(9713), BON2 = A(9714);
  await q.query("set session_replication_role = replica");
  await q.query("insert into companies (id, restaurant_id, name) values ($1,$2,'Teken BV')", [TEKEN, RA]);
  await q.query("insert into approval_settings (company_id, method, is_required, auto_lock) values ($1,'signature',true,true)", [TEKEN]);
  await q.query("insert into open_tabs (id, restaurant_id, company_id, status) values ($1,$2,$3,'open'), ($4,$2,$3,'open')", [TAB, RA, TEKEN, TAB2]);
  await q.query("insert into receipts (id, restaurant_id, open_tab_id, status, total, receipt_number) values ($1,$2,$3,'pending_approval',12.5,'T-1'), ($4,$2,$5,'linked',7,'T-2')", [BON, RA, TAB, BON2, TAB2]);
  await q.query("insert into receipt_lines (receipt_id, description, quantity, unit_price, vat_rate, line_total) values ($1,'Lunch',1,11.47,9,12.50), ($2,'Thee',2,3.21,9,7.00)", [BON, BON2]);
  await q.query("insert into approvals (receipt_id, company_id, method, status) values ($1,$2,'signature','pending')", [BON, TEKEN]);
  await q.query("set session_replication_role = origin");

  // ===== 2. module uit
  await module(false);
  as("bed"); let r = await teken(BON, { name: "Jan", signature: SIG, fingerprint: await vinger(BON) });
  ok("8 module Handtekening uit: 403, bon wacht nog", r.status === 403 && (await status(BON)) === "pending_approval", JSON.stringify(r));
  as("owner"); r = await res(await settingsRoute.PUT(req("PUT", { enabled: true, method: "signature" }), { params: { id: A(100) } }));
  ok("9 instelling 'handtekening' kiezen met module uit: 403 met uitleg, instelling ongewijzigd", r.status === 403 && /module Handtekening staat uit/.test(r.json.error ?? "")
     && (await one("select method from approval_settings where company_id=$1", [A(100)])).method === "pin", JSON.stringify(r));
  as("owner"); let pagina = await OpenTabDetailPage({ params: { id: TAB } });
  let sectie: any = null; walk(pagina, (x) => { if (Array.isArray(x.props?.initialReceipts)) sectie = x.props; });
  ok("10 scherm met module uit: methode signature, geen vingerafdruk, signatureEnabled false", sectie?.signatureEnabled === false && sectie.initialReceipts[0].approval_method === "signature"
     && !sectie.initialReceipts[0].signature_fingerprint, JSON.stringify(sectie?.initialReceipts?.[0]).slice(0, 300));

  // ===== 3. module aan: tekenen door de bediening
  await module(true);
  as("bed"); pagina = await OpenTabDetailPage({ params: { id: TAB } });
  sectie = null; walk(pagina, (x) => { if (Array.isArray(x.props?.initialReceipts)) sectie = x.props; });
  const fp = await vinger(BON);
  ok("11 scherm (bediening): signatureEnabled, bedrijfsnaam, methode signature, vingerafdruk = die van de database", sectie?.signatureEnabled === true && sectie.companyName === "Teken BV" && sectie.initialReceipts[0].approval_method === "signature"
     && sectie.initialReceipts[0].signature_fingerprint === fp, JSON.stringify(sectie?.initialReceipts?.[0]).slice(0, 300));
  as("keuken"); r = await teken(BON, { name: "Jan", signature: SIG, fingerprint: fp });
  ok("12 keuken (geen bonnenbeheer): 403, bon wacht nog", r.status === 403 && (await status(BON)) === "pending_approval", JSON.stringify(r));
  as("bed"); r = await teken(BON, { name: "J", signature: SIG, fingerprint: fp });
  ok("13 naam te kort: 400 met melding, niets gewijzigd", r.status === 400 && /naam van de klant/.test(r.json.error) && (await status(BON)) === "pending_approval", JSON.stringify(r));
  r = await teken(BON, { name: "Jan", signature: SIG, fingerprint: "0".repeat(32) });
  ok("14 verkeerde vingerafdruk: 409 'gewijzigd', niets gewijzigd", r.status === 409 && /gewijzigd/.test(r.json.error) && (await status(BON)) === "pending_approval", JSON.stringify(r));
  (cfg as any).rpcFault = "bon_ondertekenen"; r = await teken(BON, { name: "Jan", signature: SIG, fingerprint: fp }); (cfg as any).rpcFault = undefined;
  ok("15 databasefout: 500, nooit 'gelukt', bon wacht nog", r.status === 500 && /niet gelukt/.test(r.json.error) && (await status(BON)) === "pending_approval", JSON.stringify(r));
  as("mgr"); r = await res(await approve.POST(req("POST", {}), { params: { id: BON } }));
  ok("16 manager via de goedkeurroute: geweigerd (alleen de klant tekent), bon wacht nog", r.status === 400 && (await status(BON)) === "pending_approval", JSON.stringify(r));
  const ev0 = (await one("select count(*)::int n from domain_events where event_type='ApprovalCompleted'")).n;
  as("bed"); r = await teken(BON, { name: "  Jan Klant  ", signature: SIG, fingerprint: fp });
  const rg = await regel(BON);
  ok("17 bediening laat tekenen: 200 locked; regel approved door 'Jan Klant' met handtekening", r.status === 200 && r.json.status === "locked" && r.json.signedBy === "Jan Klant"
     && (await status(BON)) === "locked" && rg.status === "approved" && rg.approved_by === "Jan Klant" && rg.signature_data === SIG, JSON.stringify([r, rg.status, rg.approved_by]));
  ok("18 logboek: ApprovalCompleted (signature) en activiteit door de bediening", (await one("select count(*)::int n from domain_events where event_type='ApprovalCompleted'")).n === ev0 + 1
     && (await one("select count(*)::int n from activity_log where user_id=$1 and target_id=$2 and action like 'liet een bon ondertekenen%'", [U.bed.id, BON])).n === 1);
  r = await teken(BON, { name: "Jan", signature: SIG, fingerprint: fp });
  ok("19 nog een keer: 409 'wacht niet (meer)', regel ongewijzigd", r.status === 409 && /wacht niet/.test(r.json.error) && (await regel(BON)).approved_by === "Jan Klant", JSON.stringify(r));
  as("owner"); pagina = await OpenTabDetailPage({ params: { id: TAB } });
  sectie = null; walk(pagina, (x) => { if (Array.isArray(x.props?.initialReceipts)) sectie = x.props; });
  ok("20 scherm na tekenen: goedgekeurd door 'Jan Klant' via handtekening", sectie?.initialReceipts[0].approved_by === "Jan Klant" && sectie.initialReceipts[0].approved_method === "signature",
     JSON.stringify(sectie?.initialReceipts?.[0]).slice(0, 300));

  // ===== 4. indienen met methode handtekening, daarna tekenen (hele keten via de routes)
  as("bed"); r = await res(await reqApproval.POST(req("POST"), { params: { id: BON2 } }));
  const rg2 = await regel(BON2);
  ok("21 indienen bij een handtekeningbedrijf: bon wacht, regel signature zonder token", r.status < 300 && (await status(BON2)) === "pending_approval" && rg2.method === "signature" && rg2.status === "pending", JSON.stringify(r));
  r = await teken(BON2, { name: "Piet", signature: SIG, fingerprint: await vinger(BON2) });
  ok("22 daarna tekenen: locked", r.status === 200 && (await status(BON2)) === "locked", JSON.stringify(r));

  // ===== 4b. rekening naar een ander bedrijf terwijl de bon op een handtekening wacht: niet te ondertekenen
  const TAB3 = A(9715), BON3 = A(9716), ANDER = A(9717);
  await q.query("set session_replication_role = replica");
  await q.query("insert into companies (id, restaurant_id, name) values ($1,$2,'Ander BV')", [ANDER, RA]);
  await q.query("insert into open_tabs (id, restaurant_id, company_id, status) values ($1,$2,$3,'open')", [TAB3, RA, TEKEN]);
  await q.query("insert into receipts (id, restaurant_id, open_tab_id, status, total, receipt_number) values ($1,$2,$3,'pending_approval',4,'T-3')", [BON3, RA, TAB3]);
  await q.query("insert into approvals (receipt_id, company_id, method, status) values ($1,$2,'signature','pending')", [BON3, TEKEN]);
  await q.query("set session_replication_role = origin");
  const fpVoor = await vinger(BON3);
  await q.query("update open_tabs set company_id=$1 where id=$2", [ANDER, TAB3]);
  as("bed"); pagina = await OpenTabDetailPage({ params: { id: TAB3 } });
  sectie = null; walk(pagina, (x) => { if (Array.isArray(x.props?.initialReceipts)) sectie = x.props; });
  const fpNa = sectie?.initialReceipts?.[0]?.signature_fingerprint;
  ok("22b bedrijf van de rekening gewijzigd: scherm toont het nieuwe bedrijf, vingerafdruk is anders", sectie?.companyName === "Ander BV" && !!fpNa && fpNa !== fpVoor, JSON.stringify([sectie?.companyName, fpVoor, fpNa]));
  r = await teken(BON3, { name: "Jan", signature: SIG, fingerprint: fpVoor });
  ok("22c oude vingerafdruk (van voor de wissel): 409, niets gewijzigd", r.status === 409 && (await status(BON3)) === "pending_approval", JSON.stringify(r));
  r = await teken(BON3, { name: "Jan", signature: SIG, fingerprint: fpNa });
  ok("22d verse vingerafdruk, maar regel hoort bij het oude bedrijf: 409 'ander bedrijf', regel blijft wachten", r.status === 409 && r.json.error === COMPANY_MISMATCH
     && (await status(BON3)) === "pending_approval" && (await regel(BON3)).status === "pending", JSON.stringify(r));
  r = await teken(BON3, { name: "Jan", signature: PNG.GEEN_PNG, fingerprint: fpNa });
  ok("22e route: base64 zonder PNG geweigerd vóór de database (400)", r.status === 400 && /geldige handtekening/.test(r.json.error), JSON.stringify(r));

  // ===== 5. instelling met module aan
  as("owner"); r = await res(await settingsRoute.PUT(req("PUT", { enabled: true, method: "signature" }), { params: { id: A(105) } }));
  ok("23 instelling 'handtekening' met module aan: opgeslagen", r.status === 200 && (await one("select method from approval_settings where company_id=$1", [A(105)])).method === "signature", JSON.stringify(r));
  as("bed"); r = await res(await settingsRoute.PUT(req("PUT", { enabled: true, method: "signature" }), { params: { id: A(100) } }));
  ok("24 bediening mag de instelling niet wijzigen (rol eerst): 403", r.status === 403, JSON.stringify(r));

  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
