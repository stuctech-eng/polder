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

  // ===== stroom 1: intern goedkeuren (restaurant_confirms)
  await setMethod("restaurant_confirms");
  as("bed");
  let r = await call(tabsRoute.POST, { companyId: A100, tableNumber: "T1", guestCount: 2 });
  ok("rekening openen (bediening) 201", r.status === 201, JSON.stringify(r.json)); const tab1 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line], notes: "n" }, { id: tab1 });
  ok("bon toevoegen: 201 en direct pending_approval (bedrijf vereist goedkeuring)", r.status === 201 && r.json.receipt.status === "pending_approval", JSON.stringify(r.json)); const rec1 = r.json.receipt.id;
  ok("DB: bon pending_approval + regel + approval pending", (await one("select (select status from receipts where id=$1) s,(select count(*)::int from receipt_lines where receipt_id=$1) l,(select status from approvals where receipt_id=$1) a", [rec1])).a === "pending");
  r = await call(receiptRoute.PATCH, { notes: "andere" }, { id: rec1 });
  ok("bon in wacht bewerken: route laat toe maar database weigert (alleen foutmelding, geen wijziging)", r.status === 500 && /kan niet worden gewijzigd/.test(r.json.error ?? ""), JSON.stringify(r.json));
  r = await call(receiptRoute.DELETE, undefined, { id: rec1 });
  ok("bon in wacht verwijderen: database weigert", r.status === 500 && /kan niet worden verwijderd/.test(r.json.error ?? ""), JSON.stringify(r.json));
  r = await call(approve.POST, {}, { id: rec1 });
  ok("bediening kan niet goedkeuren (route 403)", r.status === 403, JSON.stringify(r.json));
  as("adm"); r = await call(approve.POST, {}, { id: rec1 });
  ok("administratie kan niet goedkeuren (route 403)", r.status === 403);
  as("mgr"); r = await call(approve.POST, {}, { id: rec1 });
  ok("manager keurt goed: bon locked", r.status === 200 && r.json.status === "locked", JSON.stringify(r.json));
  ok("DB: bon locked, approval approved met goedkeurder", (await one("select r.status rs,a.status a,a.approved_by ab from receipts r join approvals a on a.receipt_id=r.id where r.id=$1", [rec1])).a === "approved");
  as("bed"); r = await call(receiptRoute.PATCH, { notes: "x" }, { id: rec1 }); ok("vergrendelde bon bewerken: route 400", r.status === 400);
  r = await call(tabRoute.PATCH, { status: "closed" }, { id: tab1 }); ok("rekening sluiten (bediening)", r.status === 200 && r.json.openTab.status === "closed", JSON.stringify(r.json));
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab1 }); ok("bon op gesloten rekening: route 400", r.status === 400);
  r = await call(tabRoute.PATCH, { tableNumber: "T9" }, { id: tab1 }); ok("tafelnummer op gesloten rekening wijzigen mag nog", r.status === 200);
  r = await call(genInvoice.POST, undefined, { id: tab1 }); ok("bediening factureren: route 403", r.status === 403);
  as("owner"); r = await call(genInvoice.POST, undefined, { id: tab1 });
  ok("owner factureert: 201 + PDF-upload met upsert:false", r.status === 201 && cfg.uploads.at(-1)?.opt?.upsert === false, JSON.stringify(r.json));
  ok("DB: rekening invoiced, factuur + regel + document", (await one("select (select status from open_tabs where id=$1) s,(select count(*)::int from invoice_lines where receipt_id=$2) l", [tab1, rec1])).s === "invoiced");
  as("bed"); r = await call(tabRoute.PATCH, { tableNumber: "T10" }, { id: tab1 }); ok("gefactureerde rekening wijzigen: route 400", r.status === 400);

  // ===== stroom 2: externe link (qr): goedkeuren
  await setMethod("qr");
  as("bed"); r = await call(tabsRoute.POST, { companyId: A100 }); const tab2 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab2 }); const rec2 = r.json.receipt.id; const tok2 = r.json.approvalToken;
  ok("qr: pending + token", r.json.receipt.status === "pending_approval" && !!tok2);
  let pr = await call(publicApprove.GET, undefined, { token: tok2 }); ok("publieke link lezen (service_role)", pr.status === 200 && pr.json.approvalStatus === "pending", JSON.stringify(pr.json));
  pr = await call(publicApprove.POST, { action: "approve", approverName: "Klant BV" }, { token: tok2 });
  ok("publieke link goedkeuren: bon locked", pr.status === 200 && pr.json.status === "locked", JSON.stringify(pr.json));
  ok("DB: approval approved door klant", (await one("select a.status, a.approved_by, r.status rs from approvals a join receipts r on r.id=a.receipt_id where r.id=$1", [rec2])).approved_by === "Klant BV");
  pr = await call(publicApprove.POST, { action: "approve", approverName: "Nogmaals" }, { token: tok2 });
  ok("dezelfde link nogmaals gebruiken wordt geweigerd", pr.status === 400, JSON.stringify(pr.json));

  // ===== stroom 3: afwijzen -> opnieuw indienen -> goedkeuren
  as("bed"); r = await call(tabsRoute.POST, { companyId: A100 }); const tab3 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab3 }); const rec3 = r.json.receipt.id; const tok3 = r.json.approvalToken;
  pr = await call(publicApprove.POST, { action: "reject", approverName: "Klant", reason: "fout bedrag" }, { token: tok3 });
  ok("publieke link afwijzen: bon terug naar linked", pr.status === 200 && pr.json.status === "linked", JSON.stringify(pr.json));
  ok("DB: approval rejected met reden", (await one("select a.status, a.metadata->>'reason' reason from approvals a where a.receipt_id=$1", [rec3])).reason === "fout bedrag");
  r = await call(receiptRoute.PATCH, { notes: "gecorrigeerd" }, { id: rec3 }); ok("afgewezen bon (linked) is weer bewerkbaar", r.status === 200, JSON.stringify(r.json));
  r = await call(reqApproval.POST, undefined, { id: rec3 }); const tok3b = r.json.approvalToken;
  ok("opnieuw ter goedkeuring aanbieden (linked → pending_approval + nieuwe approval)", r.status === 200 && r.json.status === "pending_approval" && !!tok3b && tok3b !== tok3, JSON.stringify(r.json));
  ok("DB: twee approvals (rejected + pending)", (await one("select count(*)::int n from approvals where receipt_id=$1", [rec3])).n === 2);
  pr = await call(publicApprove.POST, { action: "approve", approverName: "Klant" }, { token: tok3b }); ok("nieuwe link goedkeuren: locked", pr.status === 200 && pr.json.status === "locked");
  pr = await call(publicApprove.POST, { action: "approve", approverName: "Oud" }, { token: tok3 }); ok("oude (afgewezen) link werkt niet meer", pr.status === 400);

  // ===== stroom 4: autoLock uit: approved (niet locked)
  await q.query("update approval_settings set method='restaurant_confirms', auto_lock=false where company_id=$1", [A100]);
  as("bed"); r = await call(tabsRoute.POST, { companyId: A100 }); const tab4 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab4 }); const rec4 = r.json.receipt.id;
  as("mgr"); r = await call(approve.POST, {}, { id: rec4 });
  ok("autoLock uit: manager keurt goed -> approved", r.status === 200 && r.json.status === "approved", JSON.stringify(r.json));
  as("bed"); r = await call(receiptRoute.PATCH, { notes: "x" }, { id: rec4 });
  ok("goedgekeurde (niet vergrendelde) bon bewerken: database weigert", r.status === 500, JSON.stringify(r.json));

  // ===== stroom 5: verwijderen en rekeningen zonder goedkeuring
  await q.query("update approval_settings set is_required=false, auto_lock=true where company_id=$1", [A100]);
  as("bed"); r = await call(tabsRoute.POST, { companyId: A100 }); const tab5 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line, { ...line, description: "Koffie" }] }, { id: tab5 }); const rec5 = r.json.receipt.id;
  ok("zonder goedkeuringsplicht blijft bon linked", r.json.receipt.status === "linked");
  r = await call(receiptRoute.PATCH, { notes: "ok", receiptNumber: "Z1" }, { id: rec5 }); ok("linked bon bewerken", r.status === 200);
  r = await call(tabRoute.DELETE, undefined, { id: tab5 }); ok("rekening met bon verwijderen: route 400", r.status === 400);
  r = await call(receiptRoute.DELETE, undefined, { id: rec5 }); ok("linked bon verwijderen (cascade naar regels)", r.status === 200, JSON.stringify(r.json));
  ok("DB: bon en regels weg", (await one("select (select count(*)::int from receipts where id=$1) a,(select count(*)::int from receipt_lines where receipt_id=$1) b", [rec5])).a === 0);
  r = await call(tabRoute.DELETE, undefined, { id: tab5 }); ok("lege open rekening verwijderen", r.status === 200, JSON.stringify(r.json));
  r = await call(tabsRoute.POST, { companyId: A100 }); const tab6 = r.json.openTab.id;
  r = await call(tabRoute.PATCH, { status: "closed" }, { id: tab6 }); r = await call(tabRoute.DELETE, undefined, { id: tab6 });
  ok("gesloten rekening verwijderen: route 400", r.status === 400);

  // ===== lezen (dashboard, dagafsluiting, lijsten)
  for (const k of ["owner", "mgr", "adm"]) {
    as(k); const sb = createClient("x", "user:" + U[k].id);
    const o = await sb.from("open_tabs").select("id", { count: "exact", head: true }).eq("status", "open");
    const rep = await buildDailyClosingReport(sb, RA, new Date().toISOString().slice(0, 10));
    ok(`${k}: dashboard-telling en dagafsluitingsrapport werken`, !o.error && typeof o.count === "number" && typeof rep.totalRevenue === "number", JSON.stringify(o.error));
  }
  as("bed"); r = await call(tabsRoute.GET as any, undefined, {}); ok("bediening ziet open rekeningen", r.status === 200 && r.json.openTabs.length > 0);
  r = await call(tabReceipts.GET as any, undefined, { id: tab1 }); ok("bediening ziet bonnen met regels", r.status === 200 && r.json.receipts.length === 1 && r.json.receipts[0].receipt_lines.length === 1);

  // ===== directe pogingen buiten de app om (gewone gebruikersverbinding)
  const bed = createClient("x", "user:" + U.bed.id), own = createClient("x", "user:" + U.owner.id), oB = createClient("x", "user:" + U.ownerB.id);
  let d: any;
  d = await own.from("receipts").update({ notes: "hack" }).eq("id", rec1).select("id"); ok("direct: vergrendelde bon wijzigen geweigerd", !!d.error, JSON.stringify(d));
  d = await own.from("receipts").delete().eq("id", rec1).select("id"); ok("direct: vergrendelde bon verwijderen geweigerd", !!d.error, JSON.stringify(d));
  d = await bed.from("receipts").insert({ restaurant_id: RA, open_tab_id: tab4, status: "locked" }); ok("direct: bon als locked aanmaken geweigerd", !!d.error);
  await setMethod("qr"); await q.query("update approval_settings set is_required=true where company_id=$1", [A100]);
  as("bed"); r = await call(tabsRoute.POST, { companyId: A100 }); const tab7 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab7 }); const rec7 = r.json.receipt.id;
  d = await bed.from("approvals").update({ status: "approved", approved_by: "ik" }).eq("receipt_id", rec7).select("id");
  ok("direct: bediening keurt zelf goed geweigerd (0 rijen of fout)", !!d.error || (d.data ?? []).length === 0, JSON.stringify(d));
  d = await bed.from("receipts").update({ status: "locked" }).eq("id", rec7).select("id"); ok("direct: bediening vergrendelt zelf een bon in wacht: geweigerd", !!d.error, JSON.stringify(d));
  ok("approval van rec7 nog pending, bon nog pending_approval", (await one("select a.status a, r.status r from approvals a join receipts r on r.id=a.receipt_id where r.id=$1", [rec7])).a === "pending");
  d = await bed.from("approvals").insert({ receipt_id: rec4, company_id: A100, method: "pin", status: "approved" }); ok("direct: approval als approved aanmaken geweigerd", !!d.error);
  d = await own.from("approvals").delete().eq("receipt_id", rec3).select("id"); ok("direct: approval verwijderen geweigerd (0 rijen of fout)", !!d.error || (d.data ?? []).length === 0, JSON.stringify(d));
  d = await own.from("open_tabs").update({ status: "open" }).eq("id", tab1).select("id"); ok("direct: gefactureerde rekening heropenen geweigerd", !!d.error, JSON.stringify(d));
  d = await own.from("receipt_lines").update({ unit_price: 1 }).eq("receipt_id", rec1).select("id"); ok("direct: regel van vergrendelde bon wijzigen geweigerd (0 rijen)", !!d.error || (d.data ?? []).length === 0, JSON.stringify(d));
  d = await oB.from("receipts").select("id").eq("id", rec1); ok("andere tenant ziet bon niet", (d.data ?? []).length === 0);
  d = await oB.from("open_tabs").update({ table_number: "x" }).eq("id", tab4).select("id"); ok("andere tenant kan rekening niet wijzigen", !!d.error || (d.data ?? []).length === 0);
  ok("bon rec1 onveranderd na alle pogingen", (await one("select status, notes from receipts where id=$1", [rec1])).status === "locked");


  // ===== PLAN 7b: afgewezen bon niet factureren — gedeelde scenariolijst, app en database naast elkaar
  const fs = require("fs");
  const { isRejectionBlocked, isInvoiceBlocked } = require("@/lib/approval/invoice-blocking");
  const SC = JSON.parse(fs.readFileSync(process.env.SCEN_FILE as string, "utf8")).scenarios;
  const writes = async () => { const x = await one("select (select count(*)::int from invoices) i,(select count(*)::int from invoice_lines) l,(select count(*)::int from documents) d"); return `${x.i}/${x.l}/${x.d}/${cfg.uploads.length}`; };
  const rep = async (sql: string, p: any[] = []) => { await q.query("begin"); await q.query("set local session_replication_role = replica"); const r = await q.query(sql, p); await q.query("commit"); return r.rows; };
  await setMethod("qr"); await q.query("update approval_settings set is_required=true, auto_lock=true where company_id=$1", [A100]);
  const own7 = createClient("x", "user:" + U.owner.id), bed7 = createClient("x", "user:" + U.bed.id);
  for (const sc of SC) {
    // (a) de pure app-functies op de scenario-gegevens zelf
    const tabRej = sc.receipts.some((rc: any) => isRejectionBlocked({ status: rc.status }, rc.approvals.map((s: string) => ({ status: s }))));
    const tabInv = sc.receipts.some((rc: any) => isInvoiceBlocked({ status: rc.status }, rc.approvals.map((s: string) => ({ status: s }))));
    ok(`7b ${sc.id} app-functie: afwijzingsblokkade = ${sc.expect.rejection}`, tabRej === sc.expect.rejection, sc.title);
    ok(`7b ${sc.id} app-functie: facturatieblokkade = ${sc.expect.invoice}`, tabInv === sc.expect.invoice, sc.title);
    // (b) dezelfde situatie in de echte database opbouwen; de app-functie op de DB-rijen laten oordelen
    const needMove = sc.receipts.some((rc: any) => rc.moved);
    const tabX = (await rep("insert into open_tabs (restaurant_id, company_id, status) values ($1,$2,$3) returning id", [RA, A100, needMove ? "open" : "closed"]))[0].id;
    const tabY = needMove ? (await rep("insert into open_tabs (restaurant_id, company_id, status) values ($1,$2,'open') returning id", [RA, A100]))[0].id : tabX;
    const rids: string[] = [];
    for (const rc of sc.receipts) {
      const rid = (await rep("insert into receipts (restaurant_id, open_tab_id, status, total, receipt_number) values ($1,$2,$3,5,$4) returning id", [RA, tabX, rc.status, `${sc.id}-${rids.length}`]))[0].id; rids.push(rid);
      let j = 0; for (const st of rc.approvals) { await rep("insert into approvals (receipt_id, company_id, method, status, approved_at) values ($1,$2,'qr',$3,$4)", [rid, A100, st, st === "pending" ? null : new Date(Date.now() + j * 1000).toISOString()]); j++; }
    }
    if (needMove) {   // echte verplaatsing door de bediening, daarna rekening sluiten
      for (const rid of rids) { const m = await bed7.from("receipts").update({ open_tab_id: tabY }).eq("id", rid); ok(`7b ${sc.id} bon verplaatsen naar andere open rekening`, !m.error, JSON.stringify(m)); }
      as("bed"); const cl = await call(tabRoute.PATCH, { status: "closed" }, { id: tabY }); ok(`7b ${sc.id} rekening sluiten na verplaatsing`, cl.status === 200, JSON.stringify(cl.json));
    }
    const dbReceipts = (await q.query("select id, status from receipts where open_tab_id=$1", [tabY])).rows;
    let dbRej = false, dbInv = false;
    for (const rc of dbReceipts) {
      const ap = (await q.query("select status from approvals where receipt_id=$1", [rc.id])).rows;
      dbRej = dbRej || isRejectionBlocked(rc, ap); dbInv = dbInv || isInvoiceBlocked(rc, ap);
    }
    ok(`7b ${sc.id} app-functie op rijen uit de database: zelfde uitkomst`, dbRej === sc.expect.rejection && dbInv === sc.expect.invoice, `${dbRej}/${dbInv}`);
    // (c) de route: bij facturatieblokkade nul schrijfacties en de juiste reden; anders gewoon factureren
    as("owner"); const w0 = await writes();
    const gi = await call(genInvoice.POST, undefined, { id: tabY });
    if (sc.expect.invoice) {
      const hasPending = sc.receipts.some((rc: any) => rc.status === "pending_approval");
      const msgOk = hasPending ? /wachten nog op goedkeuring/.test(gi.json.error ?? "") : /afgewezen en nog niet opnieuw goedgekeurd/.test(gi.json.error ?? "");
      ok(`7b ${sc.id} route: 400 met juiste reden (${hasPending ? "wacht op goedkeuring" : "afgewezen"})`, gi.status === 400 && msgOk, JSON.stringify(gi.json));
      ok(`7b ${sc.id} route: nul schrijfacties (geen factuur, regels, document of upload)`, (await writes()) === w0, `${w0} -> ${await writes()}`);
      ok(`7b ${sc.id} rekening nog gesloten na geweigerde factuur`, (await one("select status from open_tabs where id=$1", [tabY])).status === "closed");
      // (d) direct naar de database, buiten de app om: geweigerd precies bij afwijzingsblokkade
      const dr = await own7.from("open_tabs").update({ status: "invoiced" }).eq("id", tabY).select("id");
      if (sc.expect.rejection) ok(`7b ${sc.id} database: closed -> invoiced geweigerd (afwijzingsblokkade)`, !!dr.error && /afgewezen bon/.test(dr.error.message), JSON.stringify(dr));
      else ok(`7b ${sc.id} database: closed -> invoiced toegestaan (bekend verschil: pending_approval alleen in de app)`, !dr.error && (dr.data ?? []).length === 1, JSON.stringify(dr));
    } else {
      ok(`7b ${sc.id} route: factuur wordt gemaakt (201)`, gi.status === 201, JSON.stringify(gi.json));
      ok(`7b ${sc.id} rekening gefactureerd`, (await one("select status from open_tabs where id=$1", [tabY])).status === "invoiced");
    }
  }

  // ===== PLAN 7b: echte stroom via de routes: afwijzen -> factureren geweigerd -> opnieuw indienen -> weer afwijzen -> opnieuw indienen -> goedkeuren -> factureren
  as("bed"); r = await call(tabsRoute.POST, { companyId: A100 }); const tab8 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab8 }); const rec8 = r.json.receipt.id; const tok8 = r.json.approvalToken;
  pr = await call(publicApprove.POST, { action: "reject", approverName: "Klant", reason: "te duur" }, { token: tok8 });
  ok("7b stroom: afgewezen via publieke link, bon terug naar linked", pr.status === 200 && pr.json.status === "linked", JSON.stringify(pr.json));
  r = await call(tabRoute.PATCH, { status: "closed" }, { id: tab8 }); ok("7b stroom: rekening met afgewezen bon sluiten mag", r.status === 200);
  as("owner"); let w1 = await writes(); r = await call(genInvoice.POST, undefined, { id: tab8 });
  ok("7b stroom: factureren geweigerd (afgewezen), met uitleg", r.status === 400 && /afgewezen en nog niet opnieuw goedgekeurd/.test(r.json.error) && /opnieuw in/.test(r.json.error), JSON.stringify(r.json));
  ok("7b stroom: nul schrijfacties", (await writes()) === w1);
  let dd = await own7.from("open_tabs").update({ status: "invoiced" }).eq("id", tab8).select("id"); ok("7b stroom: direct naar de database: geweigerd", !!dd.error && /afgewezen bon/.test(dd.error.message), JSON.stringify(dd));
  as("bed"); r = await call(reqApproval.POST, undefined, { id: rec8 }); const tok8b = r.json.approvalToken;
  ok("7b stroom: opnieuw indienen op gesloten rekening werkt", r.status === 200 && r.json.status === "pending_approval" && !!tok8b, JSON.stringify(r.json));
  as("owner"); w1 = await writes(); r = await call(genInvoice.POST, undefined, { id: tab8 });
  ok("7b stroom: opnieuw ingediend maar in wacht: factureren geweigerd (bestaande melding)", r.status === 400 && /wachten nog op goedkeuring/.test(r.json.error), JSON.stringify(r.json)); ok("7b stroom: nul schrijfacties (in wacht)", (await writes()) === w1);
  pr = await call(publicApprove.POST, { action: "reject", approverName: "Klant", reason: "nog steeds te duur" }, { token: tok8b });
  ok("7b stroom: opnieuw afgewezen", pr.status === 200 && pr.json.status === "linked");
  w1 = await writes(); r = await call(genInvoice.POST, undefined, { id: tab8 });
  ok("7b stroom: na tweede afwijzing nog steeds geweigerd", r.status === 400 && /afgewezen en nog niet opnieuw goedgekeurd/.test(r.json.error), JSON.stringify(r.json)); ok("7b stroom: nul schrijfacties (tweede afwijzing)", (await writes()) === w1);
  as("bed"); r = await call(reqApproval.POST, undefined, { id: rec8 }); const tok8c = r.json.approvalToken; ok("7b stroom: derde keer indienen", r.status === 200 && !!tok8c);
  pr = await call(publicApprove.POST, { action: "approve", approverName: "Klant BV" }, { token: tok8c }); ok("7b stroom: goedgekeurd (locked)", pr.status === 200 && pr.json.status === "locked", JSON.stringify(pr.json));
  as("owner"); r = await call(genInvoice.POST, undefined, { id: tab8 }); ok("7b stroom: na goedkeuring wel factureren (201)", r.status === 201, JSON.stringify(r.json));
  ok("7b stroom: rekening gefactureerd en bon in factuurregel", (await one("select (select status from open_tabs where id=$1) s,(select count(*)::int from invoice_lines where receipt_id=$2) l", [tab8, rec8])).s === "invoiced");

  // ===== PLAN 7b: geblokkeerde bon verwijderen is de uitweg; rest wordt dan wel gefactureerd
  as("bed"); r = await call(tabsRoute.POST, { companyId: A100 }); const tab9 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab9 }); const rec9a = r.json.receipt.id; const tok9a = r.json.approvalToken;
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab9 }); const rec9b = r.json.receipt.id; const tok9b = r.json.approvalToken;
  await call(publicApprove.POST, { action: "approve", approverName: "K" }, { token: tok9a }); await call(publicApprove.POST, { action: "reject", approverName: "K", reason: "x" }, { token: tok9b });
  await call(tabRoute.PATCH, { status: "closed" }, { id: tab9 });
  as("owner"); w1 = await writes(); r = await call(genInvoice.POST, undefined, { id: tab9 }); ok("7b uitweg: rekening met goedgekeurde en afgewezen bon geweigerd", r.status === 400 && (await writes()) === w1, JSON.stringify(r.json));
  as("bed"); r = await call(receiptRoute.DELETE, undefined, { id: rec9b }); ok("7b uitweg: afgewezen bon op gesloten rekening verwijderen mag", r.status === 200, JSON.stringify(r.json));
  as("owner"); r = await call(genInvoice.POST, undefined, { id: tab9 }); ok("7b uitweg: daarna wordt de rest wel gefactureerd", r.status === 201, JSON.stringify(r.json));

  // ===== PLAN 7b: rekening zonder bonnen blijft zich gedragen als vóór 7b (geen nieuwe blokkade, geen schrijfacties)
  const emptyTab = (await rep("insert into open_tabs (restaurant_id, company_id, status) values ($1,$2,'closed') returning id", [RA, A100]))[0].id;
  as("owner"); w1 = await writes(); r = await call(genInvoice.POST, undefined, { id: emptyTab });
  ok("7b: rekening zonder bonnen: bestaande melding 'Geen bonnen gekoppeld' (400), niet door de nieuwe controle", r.status === 400 && /Geen bonnen gekoppeld/.test(r.json.error) && !/afgewezen|Goedkeuringsgegevens/.test(r.json.error), JSON.stringify(r.json));
  ok("7b: rekening zonder bonnen: nul schrijfacties en rekening blijft gesloten", (await writes()) === w1 && (await one("select status from open_tabs where id=$1", [emptyTab])).status === "closed");

  // ===== PLAN 7b: requestResubmit (de handler-logica van de knop): succes, serverfouten, onleesbaar antwoord en netwerkfout
  const { requestResubmit } = require("@/lib/approval/resubmit");
  const viaRoute = async (url: string) => { const m = url.match(/receipts\/([^/]+)\/request-approval/)!; const res = await (reqApproval.POST as any)(new Request("http://x/", { method: "POST" }), { params: { id: m[1] } }); return { ok: res.ok, json: () => res.json() }; };
  await setMethod("qr"); await q.query("update approval_settings set is_required=true, auto_lock=true where company_id=$1", [A100]);
  as("bed"); r = await call(tabsRoute.POST, { companyId: A100 }); const tab11 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab11 }); const rec11 = r.json.receipt.id;
  await call(publicApprove.POST, { action: "reject", approverName: "K", reason: "x" }, { token: r.json.approvalToken });
  await call(tabRoute.PATCH, { status: "closed" }, { id: tab11 });
  let rr = await requestResubmit(viaRoute, rec11);
  ok("7b resubmit: succes op afgewezen bon van een gesloten rekening (ok, token)", rr.ok === true && typeof rr.approvalToken === "string", JSON.stringify(rr));
  ok("7b resubmit: DB bon pending_approval met nieuwe goedkeuringsregel", (await one("select r.status s,(select count(*)::int from approvals where receipt_id=r.id) n from receipts r where r.id=$1", [rec11])).n === 2);
  rr = await requestResubmit(viaRoute, rec11);
  ok("7b resubmit: tweede keer (bon wacht al): uitleg 'wacht al op goedkeuring'", rr.ok === false && /wacht al op goedkeuring/.test(rr.error), JSON.stringify(rr));
  rr = await requestResubmit(viaRoute, rec8);
  ok("7b resubmit: vergrendelde bon: uitleg 'al afgehandeld', geen wijziging", rr.ok === false && /al afgehandeld/.test(rr.error) && (await one("select status from receipts where id=$1", [rec8])).status === "locked", JSON.stringify(rr));
  as("bed"); r = await call(tabsRoute.POST, { companyId: A100 }); const tab12 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab12 }); const rec12 = r.json.receipt.id;
  await call(publicApprove.POST, { action: "reject", approverName: "K", reason: "x" }, { token: r.json.approvalToken });
  await q.query("update approval_settings set is_required=false where company_id=$1", [A100]);
  rr = await requestResubmit(viaRoute, rec12);
  ok("7b resubmit: goedkeuring uitgezet: uitleg met uitweg (beheerder of verwijderen)", rr.ok === false && /Goedkeuring staat voor dit bedrijf uit/.test(rr.error) && /verwijder deze bon/.test(rr.error), JSON.stringify(rr));
  await q.query("update approval_settings set is_required=true where company_id=$1", [A100]);
  rr = await requestResubmit(async () => { throw new TypeError("Failed to fetch"); }, rec12);
  ok("7b resubmit: netwerkfout: geen exception, duidelijke melding, bon ongewijzigd", rr.ok === false && /Geen verbinding/.test(rr.error) && (await one("select status from receipts where id=$1", [rec12])).status === "linked", JSON.stringify(rr));
  rr = await requestResubmit(async () => ({ ok: false, json: async () => { throw new SyntaxError("Unexpected token <"); } }), rec12);
  ok("7b resubmit: onleesbaar antwoord (geen JSON): geen exception, algemene melding", rr.ok === false && /mislukt/.test(rr.error), JSON.stringify(rr));
  rr = await requestResubmit(async () => ({ ok: true, json: async () => { throw new SyntaxError("leeg"); } }), rec12);
  ok("7b resubmit: ok-antwoord zonder JSON: geen exception", rr.ok === true && rr.approvalToken === null, JSON.stringify(rr));
  rr = await requestResubmit(viaRoute, rec12);
  ok("7b resubmit: daarna lukt hij gewoon weer (geen blijvende toestand)", rr.ok === true, JSON.stringify(rr));

  // ===== PLAN 7b: uitleg bij falende hersubmit (goedkeuring uitgezet)
  as("bed"); r = await call(tabsRoute.POST, { companyId: A100 }); const tab10 = r.json.openTab.id;
  r = await call(tabReceipts.POST, { lines: [line] }, { id: tab10 }); const rec10 = r.json.receipt.id;
  await call(publicApprove.POST, { action: "reject", approverName: "K", reason: "x" }, { token: r.json.approvalToken });
  await q.query("update approval_settings set is_required=false where company_id=$1", [A100]);
  r = await call(reqApproval.POST, undefined, { id: rec10 }); ok("7b: opnieuw indienen met goedkeuring uit: 400 met herkenbare melding", r.status === 400 && /niet ingeschakeld/.test(r.json.error), JSON.stringify(r.json));
  ok("7b: bon blijft geblokkeerd (linked, afgewezen)", (await one("select r.status s from receipts r where r.id=$1", [rec10])).s === "linked");
  await q.query("update approval_settings set is_required=true where company_id=$1", [A100]);

  console.log(out.join("\n")); console.log(`\n${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
