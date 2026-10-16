// Stap 14b: factureren blokkeren bij bonnen die niet zijn goedgekeurd als het bedrijf goedkeuring vereist (alleen app).
// Echte factuurroute, indienroute, goedkeurroute en pagina; database met 0042. Bouwen: node build19.js <repo>;
// draaien: PGHOST=… PGPORT=… PGUSER=… TESTDB=… NODE_PATH=… node t19.js
import * as genInvoice from "@/app/api/open-tabs/[id]/generate-invoice/route";
import * as reqApproval from "@/app/api/receipts/[id]/request-approval/route";
import * as approve from "@/app/api/receipts/[id]/approve/route";
import OpenTabDetailPage from "@/app/(dashboard)/open-tabs/[id]/page";
import { invoiceBlockReason } from "@/lib/approval/invoice-blocking";
// @ts-ignore
import { cfg, end } from "@supabase/supabase-js";
import { Client } from "pg";
process.env.SUPABASE_SERVICE_ROLE_KEY = "service"; process.env.NEXT_PUBLIC_SUPABASE_URL = "x"; process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "anon";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const RA = "a0000000-0000-0000-0000-000000000001";
const A = (n: number) => `a0000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
function walk(el: any, f: (e: any) => void) {
  if (el == null || typeof el !== "object") return;
  if (Array.isArray(el)) return el.forEach((x) => walk(x, f));
  f(el); walk(el.props?.children, f);
}
const texts = (el: any) => { const t: string[] = []; walk(el, (e) => { const c = e.props?.children; (Array.isArray(c) ? c : [c]).forEach((x: any) => (typeof x === "string" || typeof x === "number") && t.push(String(x))); }); return t.join(" "); };
(async () => {
  const q = new Client({ host: process.env.PGHOST, port: +(process.env.PGPORT || 55432), database: process.env.TESTDB, user: process.env.PGUSER });
  await q.connect();
  const one = async (sql: string, p: any[] = []) => (await q.query(sql, p)).rows[0] ?? {};
  const uid = async (e: string) => (await one("select id from auth.users where email=$1", [e])).id;
  const U: any = { owner: { id: await uid("a.owner@staging.test") }, mgr: { id: await uid("a.manager@staging.test") } };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const req = (method: string, body?: any) => new Request("http://x/", { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const res = async (r: Response) => ({ status: r.status, json: await r.json().catch(() => ({})) });
  const factureer = async (tab: string) => { as("owner"); return res(await genInvoice.POST(req("POST"), { params: { id: tab } })); };
  const status = async (id: string) => (await one("select status from receipts where id=$1", [id])).status;
  const tabStatus = async (id: string) => (await one("select status from open_tabs where id=$1", [id])).status;
  // alles wat factureren schrijft: facturen (= ook het factuurnummer, dat telt de facturen), regels, documenten, uploads, events, log
  const writes = async () => { const x = await one(`select (select count(*)::int from invoices) i, (select count(*)::int from invoice_lines) l, (select count(*)::int from documents) d,
      (select count(*)::int from domain_events where event_type='InvoiceGenerated') e, (select count(*)::int from activity_log where action like 'genereerde factuur%') a`); return `${x.i}/${x.l}/${x.d}/${x.e}/${x.a}/${cfg.uploads.length}`; };
  const nulSchrijf = async (tab: string, w0: string) => (await writes()) === w0 && (await tabStatus(tab)) === "closed";

  // ===== opzet (als postgres, replica): bedrijven VEREIST (restaurant_confirms, verplicht), VRIJ (geen instelling), UIT (instelling, niet verplicht)
  const VEREIST = A(9810), VRIJ = A(9820), UIT = A(9830);
  await q.query("set session_replication_role = replica");
  for (const [c, n] of [[VEREIST, "Vereist BV"], [VRIJ, "Vrij BV"], [UIT, "Uit BV"]]) await q.query("insert into companies (id, restaurant_id, name) values ($1,$2,$3) on conflict do nothing", [c, RA, n]);
  await q.query("delete from approval_settings where company_id in ($1,$2,$3)", [VEREIST, VRIJ, UIT]);
  await q.query("insert into approval_settings (company_id, method, is_required, auto_lock) values ($1,'restaurant_confirms',true,true), ($2,'restaurant_confirms',false,true)", [VEREIST, UIT]);
  let n = 9900;
  const rekening = async (comp: string, bonnen: [string, string[]][], tabStatus = "closed") => {
    const tab = A(n++);
    await q.query("insert into open_tabs (id, restaurant_id, company_id, status) values ($1,$2,$3,$4)", [tab, RA, comp, tabStatus]);
    const ids: string[] = [];
    for (const [st, regels] of bonnen) {
      const id = A(n++); ids.push(id);
      await q.query("insert into receipts (id, restaurant_id, open_tab_id, status, total, receipt_number) values ($1,$2,$3,$4,5,$5)", [id, RA, tab, st, `R${n}`]);
      for (const r of regels) await q.query("insert into approvals (receipt_id, company_id, method, status) values ($1,$2,'restaurant_confirms',$3)", [id, comp, r]);
    }
    return { tab, ids };
  };
  const vrij = await rekening(VRIJ, [["linked", []], ["draft", []]]);
  const uit = await rekening(UIT, [["linked", []]]);
  const goed = await rekening(VEREIST, [["locked", ["approved"]], ["approved", ["approved"]]]);
  const zonderRegel = await rekening(VEREIST, [["locked", []]]);
  const nietIngediend = await rekening(VEREIST, [["linked", []]]);
  const draft = await rekening(VEREIST, [["draft", []]]);
  const wacht = await rekening(VEREIST, [["pending_approval", ["pending"]]]);
  const afgewezen = await rekening(VEREIST, [["linked", ["rejected"]]]);
  const gemengd = await rekening(VEREIST, [["locked", ["approved"]], ["pending_approval", ["pending"]], ["linked", []]]);
  const later = await rekening(UIT, [["linked", []], ["linked", []]]);
  const wissel = await rekening(VEREIST, [["linked", []]]);
  const fout1 = await rekening(VEREIST, [["locked", ["approved"]]]), fout2 = await rekening(VEREIST, [["locked", ["approved"]]]);
  const fout3 = await rekening(VEREIST, [["locked", ["approved"]]]);
  const mislukt = await rekening(VEREIST, [["linked", []]]);
  await q.query("set session_replication_role = origin");

  // ===== 1. de regel zelf
  ok("1 regel: zonder verplichting blijft het oude oordeel (linked = niet geblokkeerd)", invoiceBlockReason({ status: "linked" }, []) === null && invoiceBlockReason({ status: "linked" }, [], false) === null);
  ok("2 regel: met verplichting blokkeert alles behalve approved/locked (linked, draft, onbekend)",
     ["linked", "draft", "iets_anders"].every((s) => invoiceBlockReason({ status: s }, [], true) === "not_submitted")
     && invoiceBlockReason({ status: "approved" }, [], true) === null && invoiceBlockReason({ status: "locked" }, [], true) === null);
  ok("3 regel: wacht en afgewezen houden hun eigen reden", invoiceBlockReason({ status: "pending_approval" }, [{ status: "pending" }], true) === "pending"
     && invoiceBlockReason({ status: "linked" }, [{ status: "rejected" }], true) === "rejected");

  // ===== 2. de factuurroute
  let w0 = await writes(); let r = await factureer(vrij.tab);
  ok("4 bedrijf zonder instelling: factureren werkt zoals altijd (201, linked en draft mee)", r.status === 201 && (await tabStatus(vrij.tab)) === "invoiced", JSON.stringify(r.json).slice(0, 200));
  r = await factureer(uit.tab);
  ok("5 bedrijf met instelling 'niet verplicht': factureren werkt (201)", r.status === 201 && (await tabStatus(uit.tab)) === "invoiced", JSON.stringify(r.json).slice(0, 200));
  r = await factureer(goed.tab);
  ok("6 verplicht en alle bonnen goedgekeurd (locked en approved): 201", r.status === 201 && (await tabStatus(goed.tab)) === "invoiced", JSON.stringify(r.json).slice(0, 200));
  r = await factureer(zonderRegel.tab);
  ok("7 verplicht, bon locked zonder goedkeuringsregel: mag mee (status bewaakt door de database)", r.status === 201, JSON.stringify(r.json).slice(0, 200));
  for (const [nm, rk, re] of [["linked, nooit ingediend", nietIngediend, /R\d+ is nog niet goedgekeurd en dit bedrijf vereist goedkeuring/], ["draft", draft, /nog niet goedgekeurd en dit bedrijf vereist goedkeuring/],
      ["wacht op goedkeuring", wacht, /wachten nog op goedkeuring/], ["afgewezen", afgewezen, /afgewezen en nog niet opnieuw goedgekeurd/]] as any) {
    w0 = await writes(); r = await factureer(rk.tab);
    ok(`8 verplicht, bon ${nm}: 400 met de juiste reden, niets aangemaakt (geen factuurnummer, regels, document, upload, event, log), rekening blijft gesloten`,
       r.status === 400 && re.test(r.json.error ?? "") && (await nulSchrijf(rk.tab, w0)), `${JSON.stringify(r.json)} ${w0} -> ${await writes()}`);
  }
  w0 = await writes(); r = await factureer(gemengd.tab);
  const e = r.json.error ?? "";
  ok("9 drie bonnen (goed, wacht, niet ingediend): beide problemen in een melding, de niet-ingediende bon bij naam, niets aangemaakt",
     r.status === 400 && /wachten nog op goedkeuring/.test(e) && /bon R\d+ is nog niet goedgekeurd/.test(e)
     && (r.json.blockedReceiptIds ?? []).length === 1 && r.json.blockedReceiptIds[0] === gemengd.ids[2] && (await nulSchrijf(gemengd.tab, w0)), `${JSON.stringify(r.json)}`);

  // fail closed
  for (const [nm, fault, tab] of [["instelling: foutmelding", { table: "approval_settings", mode: "error" }, fout1.tab], ["instelling: exception", { table: "approval_settings", mode: "throw" }, fout2.tab],
      ["goedkeuringsregels: foutmelding", { table: "approvals", mode: "error" }, fout3.tab]] as any) {
    w0 = await writes(); (cfg as any).fault = fault; r = await factureer(tab); (cfg as any).fault = undefined;
    ok(`10 ${nm} niet te lezen: 500, niets aangemaakt, rekening blijft gesloten (nooit 'niet vereist' aangenomen)`,
       r.status === 500 && (await nulSchrijf(tab, w0)), `${JSON.stringify(r.json)} ${w0} -> ${await writes()}`);
  }
  r = await factureer(fout1.tab);
  ok("11 zelfde rekening daarna zonder fout: 201 (de fout was de enige reden)", r.status === 201, JSON.stringify(r.json).slice(0, 200));

  // juiste bedrijf: de eis van het HUIDIGE bedrijf van de rekening telt
  await q.query("update open_tabs set company_id=$1 where id=$2", [VRIJ, wissel.tab]);
  r = await factureer(wissel.tab);
  ok("12 rekening gewisseld naar een bedrijf zonder verplichting: 201 (eis van het huidige bedrijf, niet van het oude)", r.status === 201, JSON.stringify(r.json).slice(0, 200));

  // ===== 3. goedkeuring later aangezet, scherm, indienen, goedkeuren, factureren
  await q.query("update approval_settings set is_required=true where company_id=$1", [UIT]);
  w0 = await writes(); r = await factureer(later.tab);
  ok("13 goedkeuring aangezet terwijl er al bonnen op de rekening staan: 400 met beide bonnen, niets aangemaakt",
     r.status === 400 && (r.json.blockedReceiptIds ?? []).length === 2 && (await nulSchrijf(later.tab, w0)), JSON.stringify(r.json));
  as("owner");
  const pagina = await OpenTabDetailPage({ params: { id: later.tab } });
  let bonnen: any[] = []; walk(pagina, (x) => { if (Array.isArray(x.props?.initialReceipts)) bonnen = x.props.initialReceipts; });
  ok("14 scherm: beide bonnen 'nog niet ingediend' (knop Indienen) en bovenaan de waarschuwing met het aantal",
     bonnen.length === 2 && bonnen.every((b) => b.submission_needed === true) && /2 bonnen zijn\s+nog niet ingediend/.test(texts(pagina)), JSON.stringify(bonnen.map((b) => b.submission_needed)) + texts(pagina).slice(0, 200));
  // indienen mislukt
  as("mgr"); (cfg as any).rpcFault = "bon_indienen";
  r = await res(await reqApproval.POST(req("POST"), { params: { id: mislukt.ids[0] } })); (cfg as any).rpcFault = undefined;
  w0 = await writes(); const r2 = await factureer(mislukt.tab);
  ok("15 indienen mislukt: zichtbare fout, bon blijft linked, factureren blijft geblokkeerd", r.status >= 400 && !!r.json.error && (await status(mislukt.ids[0])) === "linked"
     && r2.status === 400 && (await nulSchrijf(mislukt.tab, w0)), JSON.stringify([r, r2.status]));
  // indienen lukt, maar nog niet goedgekeurd
  as("mgr");
  for (const id of later.ids) await reqApproval.POST(req("POST"), { params: { id } });
  ok("16 indienen: beide bonnen wachten nu op goedkeuring", (await status(later.ids[0])) === "pending_approval" && (await status(later.ids[1])) === "pending_approval");
  r = await res(await reqApproval.POST(req("POST"), { params: { id: later.ids[0] } }));
  ok("17 nog eens indienen: geweigerd, geen tweede regel", r.status === 400 && (await one("select count(*)::int n from approvals where receipt_id=$1", [later.ids[0]])).n === 1, JSON.stringify(r));
  w0 = await writes(); r = await factureer(later.tab);
  ok("18 na indienen, voor goedkeuring: factureren nog steeds geblokkeerd (wacht), niets aangemaakt", r.status === 400 && /wachten nog op goedkeuring/.test(r.json.error ?? "") && (await nulSchrijf(later.tab, w0)), JSON.stringify(r.json));
  as("mgr"); await approve.POST(req("POST", {}), { params: { id: later.ids[0] } });
  w0 = await writes(); r = await factureer(later.tab);
  ok("19 een van de twee goedgekeurd: nog steeds geblokkeerd", r.status === 400 && (await nulSchrijf(later.tab, w0)), JSON.stringify(r.json));
  as("mgr"); await approve.POST(req("POST", {}), { params: { id: later.ids[1] } });
  r = await factureer(later.tab);
  ok("20 beide goedgekeurd: factureren lukt (201)", r.status === 201 && (await tabStatus(later.tab)) === "invoiced" && (await status(later.ids[0])) === "locked", JSON.stringify(r.json).slice(0, 200));

  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
