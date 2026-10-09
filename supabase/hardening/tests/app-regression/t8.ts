import * as tabsRoute from "@/app/api/open-tabs/route";
import * as tabRoute from "@/app/api/open-tabs/[id]/route";
import * as tabReceipts from "@/app/api/open-tabs/[id]/receipts/route";
import * as genInvoice from "@/app/api/open-tabs/[id]/generate-invoice/route";
import * as receiptRoute from "@/app/api/receipts/[id]/route";
import * as reqApproval from "@/app/api/receipts/[id]/request-approval/route";
import * as approve from "@/app/api/receipts/[id]/approve/route";
import * as publicApprove from "@/app/api/public-approve/[token]/route";
import { buildDailyClosingReport } from "@/lib/daily-closing/daily-closing-service";
// @ts-ignore
import { createClient, cfg, end } from "@supabase/supabase-js";
import { Client } from "pg";
process.env.SUPABASE_SERVICE_ROLE_KEY = "service"; process.env.NEXT_PUBLIC_SUPABASE_URL = "x";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const A100 = "a0000000-0000-0000-0000-000000000100";
(async () => {
  const q = new Client({ host: "/home/pgtest", port: 55432, database: "s3", user: "pgtest" }); await q.connect();
  const uid = async (e: string) => (await q.query("select id from auth.users where email=$1", [e])).rows[0].id;
  const RA = (await q.query("select restaurant_id from users where id=$1", [await uid("a.owner@staging.test")])).rows[0].restaurant_id;
  const U: any = {};
  for (const [k, e, role] of [["owner", "a.owner@staging.test", "owner"], ["mgr", "a.manager@staging.test", "manager"], ["adm", "a.admin@staging.test", "administratie"], ["bed", "a.bediening@staging.test", "bediening"], ["ownerB", "b.owner@staging.test", "owner"]] as const)
    U[k] = { id: await uid(e), role, restaurantId: k === "ownerB" ? (await q.query("select restaurant_id from users where id=$1", [await uid(e)])).rows[0].restaurant_id : RA };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const call = async (fn: Function, body?: any, params?: any) => {
    const r: Response = await fn(new Request("http://x/", { method: "POST", headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) }), { params });
    return { status: r.status, json: await r.json().catch(() => ({})) };
  };
  const one = async (sql: string, p: any[] = []) => (await q.query(sql, p)).rows[0] ?? {};
  const setMethod = (m: string) => q.query("update approval_settings set method=$1, is_required=true, auto_lock=true where company_id=$2", [m, A100]);
  const line = { description: "Lunch", quantity: 2, unitPrice: 10, vatRate: 9 };
  // ===== VOORCONTROLE APP-RELEASE ZONDER MIGRATIE 0023 (database staat op 0022)
  const def = (await one("select pg_get_functiondef('public.open_tabs_guard()'::regprocedure) d")).d as string;
  ok("uitgangspunt: database heeft de 0023-controle NIET (app staat er alleen voor)", !/afgewezen bon is nog niet opnieuw goedgekeurd/.test(def));
  const fs = require("fs");
  const SC = JSON.parse(fs.readFileSync(process.env.SCEN_FILE as string, "utf8")).scenarios;
  const rep = async (sql: string, p: any[] = []) => { await q.query("begin"); await q.query("set local session_replication_role = replica"); const x = await q.query(sql, p); await q.query("commit"); return x.rows; };
  const writes = async () => { const x = await one("select (select count(*)::int from invoices) i,(select count(*)::int from invoice_lines) l,(select count(*)::int from documents) d"); return `${x.i}/${x.l}/${x.d}/${cfg.uploads.length}`; };
  await setMethod("qr");
  const mk = async (sc: any) => {
    const tab = (await rep("insert into open_tabs (restaurant_id, company_id, status) values ($1,$2,'closed') returning id", [RA, A100]))[0].id;
    let n = 0;
    for (const rc of sc.receipts) {
      const rid = (await rep("insert into receipts (restaurant_id, open_tab_id, status, total, receipt_number) values ($1,$2,$3,5,$4) returning id", [RA, tab, rc.status, `${sc.id}-${n++}`]))[0].id;
      let j = 0; for (const st of rc.approvals) await rep("insert into approvals (receipt_id, company_id, method, status, approved_at) values ($1,$2,'qr',$3,$4)", [rid, A100, st, st === "pending" ? null : new Date(Date.now() + j++ * 1000).toISOString()]);
    }
    return tab as string;
  };
  as("owner");
  // 1. alle 14 scenario's: geblokkeerd -> 400 en NUL schrijfacties; niet geblokkeerd -> 201 (bestaande flow intact)
  for (const sc of SC) {
    const tab = await mk(sc); const w0 = await writes();
    const gi = await call(genInvoice.POST, undefined, { id: tab });
    if (sc.expect.invoice) {
      ok(`${sc.id} zonder 0023: route 400 en nul schrijfacties (factuur, regels, document, upload)`, gi.status === 400 && (await writes()) === w0, `${gi.status} ${w0} -> ${await writes()} ${JSON.stringify(gi.json)}`);
      ok(`${sc.id} zonder 0023: rekening blijft gesloten`, (await one("select status from open_tabs where id=$1", [tab])).status === "closed");
    } else {
      ok(`${sc.id} zonder 0023: bestaande flow intact: 201 en rekening gefactureerd`, gi.status === 201 && (await one("select status from open_tabs where id=$1", [tab])).status === "invoiced", JSON.stringify(gi.json));
      ok(`${sc.id} zonder 0023: factuur, factuurregel, document en upload zijn gemaakt`, (await writes()) !== w0);
    }
  }
  // 2. de goedkeuringsquery faalt (foutmelding) -> fail closed, nul schrijfacties
  const rejSc = SC.find((s: any) => s.expect.rejection), okSc = SC.find((s: any) => !s.expect.invoice && s.receipts.length === 1);
  for (const [label, mode] of [["foutmelding", "error"], ["exception", "throw"]]) {
    for (const [nm, sc] of [["afgewezen bon", rejSc], ["goedgekeurde bon", okSc]] as any) {
      const tab = await mk(sc); const w0 = await writes();
      (cfg as any).fault = { table: "approvals", mode };
      let status = 0, msg = "", thrown = false;
      try { const gi = await call(genInvoice.POST, undefined, { id: tab }); status = gi.status; msg = gi.json.error ?? ""; } catch { thrown = true; }
      (cfg as any).fault = null;
      ok(`approvals-query faalt (${label}), ${nm}: geen factuur/regels/document/upload`, (await writes()) === w0 && (await one("select status from open_tabs where id=$1", [tab])).status === "closed", `${w0} -> ${await writes()}`);
      if (mode === "error") ok(`approvals-query faalt (foutmelding), ${nm}: fail closed met 500 en duidelijke melding`, status === 500 && /Goedkeuringsgegevens/.test(msg), `${status} ${msg}`);
      else ok(`approvals-query faalt (exception), ${nm}: route stopt (fout) voor er iets is geschreven`, thrown || status >= 500);
    }
  }
  // 3. aanvraag vroegtijdig afgebroken (AbortSignal al afgebroken): afgewezen bon blijft geblokkeerd, nul schrijfacties
  {
    const tab = await mk(rejSc); const w0 = await writes(); const ac = new AbortController(); ac.abort();
    let status = 0, thrown = false;
    try { const res: Response = await (genInvoice.POST as any)(new Request("http://x/", { method: "POST", signal: ac.signal }), { params: { id: tab } }); status = res.status; } catch { thrown = true; }
    ok("afgebroken aanvraag, afgewezen bon: geblokkeerd (400) of gestopt, nul schrijfacties", (status === 400 || thrown) && (await writes()) === w0, `${status} ${thrown}`);
  }
  // 4. bewijs dat alle controles VOOR de eerste schrijfactie staan (broncode-volgorde in de route)
  const src = fs.readFileSync("/home/claude/polder/app/api/open-tabs/[id]/generate-invoice/route.ts", "utf8");
  const iBlock = src.indexOf("invoiceBlockReason(r,"), iFirstWrite = Math.min(...["from(\"invoices\")\n    .insert", ".insert(", "storage"].map((k) => src.indexOf(k)).filter((x) => x >= 0));
  ok("route: de blokkadecontrole staat vóór de eerste insert/upload", iBlock > 0 && iBlock < src.indexOf("\"invoices\")\n    .insert") && iBlock < src.indexOf(".insert(invoiceLines)") && iBlock < src.indexOf("storage\n"), `${iBlock}`);
  console.log(out.join("\n")); console.log(`\n${pass} PASS, ${fail} FAIL`); await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch((e) => { console.log(out.join("\n")); console.log("CRASH", e); process.exit(2); });
