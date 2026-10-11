// Fase 4 (migraties 0028-0030, modules per restaurant): app-test tegen een lokale database MET 0030.
// Echte routes, pagina's (als element-boom), feature-service, platform-service en de databasewacht; alleen de Supabase-clients,
// react.cache en de mailer zijn gestubd. Bouwen: node build12.js <repo>; draaien: PGHOST=… PGPORT=… PGUSER=… TESTDB=… NODE_PATH=… node t12.js
import { isFeatureOn } from "@/lib/features/feature-service";
import DashboardLayout from "@/app/(dashboard)/layout";
import DailyClosingPage from "@/app/(dashboard)/daily-closing/page";
import InvoicesPage from "@/app/(dashboard)/invoices/page";
import CompanyDetailPage from "@/app/(dashboard)/companies/[id]/page";
import * as dailyClosing from "@/app/api/daily-closing/route";
import * as payments from "@/app/api/invoices/[id]/payments/route";
import * as invoiceRoute from "@/app/api/invoices/[id]/route";
import * as approvalSettings from "@/app/api/companies/[id]/approval-settings/route";
import * as approveRoute from "@/app/api/receipts/[id]/approve/route";
import * as requestApproval from "@/app/api/receipts/[id]/request-approval/route";
import * as newReceipt from "@/app/api/open-tabs/[id]/receipts/route";
import * as publicApprove from "@/app/api/public-approve/[token]/route";
import * as moduleRoute from "@/app/api/platform/restaurants/[id]/modules/route";
import * as restaurantsRoute from "@/app/api/platform/restaurants/route";
// @ts-ignore
import { cfg, end } from "@supabase/supabase-js";
import { Client } from "pg";
process.env.SUPABASE_SERVICE_ROLE_KEY = "service"; process.env.NEXT_PUBLIC_SUPABASE_URL = "x"; process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "anon";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const RA = "a0000000-0000-0000-0000-000000000001", RB = "b0000000-0000-0000-0000-000000000001", ORPH = "c0000000-0000-0000-0000-000000000001";
const A = (n: number) => `a0000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
const B = (n: number) => `b0000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
// element-boom doorlopen (pagina's zijn server-componenten die React-elementen teruggeven)
function walk(el: any, f: (e: any) => void) {
  if (el == null || typeof el !== "object") return;
  if (Array.isArray(el)) return el.forEach((x) => walk(x, f));
  f(el); walk(el.props?.children, f);
}
const texts = (el: any) => { const t: string[] = []; walk(el, (e) => { const c = e.props?.children; (Array.isArray(c) ? c : [c]).forEach((x: any) => typeof x === "string" && t.push(x)); }); return t.join(" "); };
const hrefs = (el: any) => { const h: string[] = []; walk(el, (e) => e.props?.href && h.push(e.props.href)); return h; };
const types = (el: any) => { const t: string[] = []; walk(el, (e) => typeof e.type === "function" && t.push(e.type.name)); return t; };
(async () => {
  const q = new Client({ host: process.env.PGHOST, port: +(process.env.PGPORT || 55432), database: process.env.TESTDB, user: process.env.PGUSER });
  await q.connect();
  const one = async (sql: string, p: any[] = []) => (await q.query(sql, p)).rows[0] ?? {};
  const uid = async (e: string) => (await one("select id from auth.users where email=$1", [e])).id;
  const U: any = { owner: { id: await uid("a.owner@staging.test") }, bed: { id: await uid("a.bediening@staging.test") },
                   ownerB: { id: await uid("b.owner@staging.test") }, admin: { id: ORPH } };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const zet = (key: string, aan: boolean | null, r = RA) => aan === null
    ? q.query("delete from restaurant_features where restaurant_id=$1 and feature=$2", [r, key])
    : q.query("insert into restaurant_features values ($1,$2,$3,now()) on conflict (restaurant_id, feature) do update set enabled=excluded.enabled", [r, key, aan]);
  const req = (method: string, body?: any) => new Request("http://x/", { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const res = async (r: Response) => ({ status: r.status, json: await r.json().catch(() => ({})) });
  const tel = async () => { const x = await one(`select (select count(*)::int from payments) p, (select count(*)::int from daily_closings) d, (select count(*)::int from approval_settings) s,
      (select string_agg(status, ',' order by id) from approvals) a, (select string_agg(status, ',' order by id) from receipts) r, (select string_agg(status, ',' order by id) from invoices) i`); return JSON.stringify(x); };
  const mails = () => ((globalThis as any).__mails ?? []).length;
  const UIT = /module staat uit/i;

  // ===== 1. standaard aan + menu
  as("owner");
  ok("1 bestaande restaurants: alle 3 modules standaard aan", (await isFeatureOn("daily_closing")) && (await isFeatureOn("payment_registration")) && (await isFeatureOn("approval")));
  ok("2a menu met module aan: Dagafsluiting zichtbaar", hrefs(await DashboardLayout({ children: null })).includes("/daily-closing"));
  await zet("daily_closing", false);
  ok("2b menu met module uit: Dagafsluiting verborgen, kern blijft", (() => { return true; })() && !hrefs(await DashboardLayout({ children: null })).includes("/daily-closing"));
  const kern = hrefs(await DashboardLayout({ children: null }));
  ok("2c kern blijft in het menu (Dashboard, Bedrijven, Rekeningen, Facturen, Team)", ["/dashboard", "/companies", "/open-tabs", "/invoices", "/team"].every((h) => kern.includes(h)), kern.join(","));

  // ===== 3/4. dagafsluiting uit: pagina en API
  ok("3 directe navigatie dagafsluiting (uit): melding 'module staat uit', geen scherm", UIT.test(texts(await DailyClosingPage())) && !types(await DailyClosingPage()).includes("DailyClosingUI"));
  let s0 = await tel(); let r = await res(await dailyClosing.POST(req("POST", { date: "2026-10-12" })));
  ok("4a dagafsluiting POST (uit): 403 'module staat uit', niets geschreven", r.status === 403 && UIT.test(r.json.error) && (await tel()) === s0, JSON.stringify(r));
  r = await res(await dailyClosing.GET(new Request("http://x/?date=2026-10-12")));
  ok("4b dagafsluiting GET (uit): 403", r.status === 403, JSON.stringify(r));
  as("ownerB"); r = await res(await dailyClosing.GET(new Request("http://x/?date=2026-10-12")));
  ok("8 A uit raakt B niet: owner B dagafsluiting GET 200", r.status === 200, JSON.stringify(r).slice(0, 200));
  as("owner"); await zet("daily_closing", null);
  ok("13a weer aan: pagina toont het scherm", types(await DailyClosingPage()).includes("DailyClosingUI"));
  // rol blijft gelden, feature geeft geen extra recht
  as("bed"); r = await res(await dailyClosing.GET(new Request("http://x/?date=2026-10-12")));
  ok("5 module aan, rol mist (bediening): dagafsluiting 403 met rolmelding", r.status === 403 && !UIT.test(r.json.error), JSON.stringify(r));
  s0 = await tel(); r = await res(await payments.POST(req("POST", { amount: 1 }), { params: { id: A(501) } }));
  ok("6 module aan geeft geen extra recht: bediening kan geen betaling registreren (403, niets geschreven)", r.status === 403 && (await tel()) === s0, JSON.stringify(r));
  // controlefout = uit
  as("owner"); cfg.rpcFault = "my_feature";
  r = await res(await dailyClosing.GET(new Request("http://x/?date=2026-10-12")));
  ok("7 fout in de featurecontrole: geweigerd (403), menu verbergt de module", r.status === 403 && !hrefs(await DashboardLayout({ children: null })).includes("/daily-closing"), JSON.stringify(r));
  cfg.rpcFault = undefined;

  // ===== 9/10. betalingen uit
  await zet("payment_registration", false);
  s0 = await tel(); r = await res(await payments.POST(req("POST", { amount: 1 }), { params: { id: A(501) } }));
  ok("10a betaling registreren (uit): 403, niets geschreven", r.status === 403 && UIT.test(r.json.error) && (await tel()) === s0, JSON.stringify(r));
  r = await res(await invoiceRoute.PATCH(req("PATCH", { status: "paid" }), { params: { id: A(501) } }));
  ok("10b factuur handmatig op betaald (uit): 403, niets gewijzigd", r.status === 403 && (await tel()) === s0, JSON.stringify(r));
  r = await res(await payments.GET(req("GET"), { params: { id: A(502) } }));
  ok("10c bestaande betalingen lezen (uit): 200", r.status === 200 && (r.json.payments ?? []).length > 0, JSON.stringify(r).slice(0, 200));
  r = await res(await invoiceRoute.PATCH(req("PATCH", { status: "sent" }), { params: { id: A(500) } }));
  ok("10d factuur op verzonden zetten (uit): 200 (kern)", r.status === 200, JSON.stringify(r));
  const lijst = await InvoicesPage(); const items: any[] = []; walk(lijst, (e) => e.props?.invoice && items.push(e.props));
  ok("10e factuurlijst (uit): facturen zichtbaar, betaalknop uit", items.length >= 3 && items.every((p) => p.paymentsEnabled === false), String(items.length));
  await zet("payment_registration", null);
  r = await res(await payments.POST(req("POST", { amount: 1, method: "cash" }), { params: { id: A(501) } }));
  ok("13b betalingen weer aan: registreren werkt", r.status === 200 || r.status === 201, JSON.stringify(r));

  // ===== 11/12. goedkeuring uit
  await q.query("update approval_settings set method='email', notify_email='x@staging.test' where company_id=$1", [A(100)]);
  await q.query("begin; set local session_replication_role = replica; insert into receipts (id, restaurant_id, status, total) values ($1,$2,'pending_approval',5); insert into approvals (id, receipt_id, company_id, method, status, verification_code) values ($3,$1,$4,'qr','pending','tok-fase4'); commit;", [A(9201), RA, A(9202), A(100)]).catch(async () => {
    await q.query("set session_replication_role = replica");
    await q.query("insert into receipts (id, restaurant_id, status, total) values ($1,$2,'pending_approval',5)", [A(9201), RA]);
    await q.query("insert into approvals (id, receipt_id, company_id, method, status, verification_code) values ($1,$2,$3,'qr','pending','tok-fase4')", [A(9202), A(9201), A(100)]);
    await q.query("set session_replication_role = origin"); });
  await q.query("set session_replication_role = replica");
  await q.query("insert into receipts (id, restaurant_id, status, total) values ($1,$2,'locked',5) on conflict do nothing", [A(9203), RA]);
  await q.query("insert into approvals (id, receipt_id, company_id, method, status, verification_code, approved_at) values ($1,$2,$3,'qr','approved','tok-oud',now()) on conflict do nothing", [A(9204), A(9203), A(100)]);
  await q.query("set session_replication_role = origin");
  await zet("approval", false);
  s0 = await tel();
  r = await res(await approvalSettings.GET(req("GET"), { params: { id: A(100) } }));
  ok("11a instellingen lezen (uit): 403", r.status === 403, JSON.stringify(r));
  r = await res(await approvalSettings.PUT(req("PUT", { enabled: false, method: null }), { params: { id: A(100) } }));
  ok("11b instellingen wijzigen (uit): 403, niets gewijzigd", r.status === 403 && (await tel()) === s0, JSON.stringify(r));
  r = await res(await approveRoute.POST(req("POST", {}), { params: { id: A(9201) } }));
  ok("11c goedkeuren met PIN/restaurant (uit): 403, niets gewijzigd", r.status === 403 && (await tel()) === s0, JSON.stringify(r));
  const m0 = mails();
  r = await res(await requestApproval.POST(req("POST"), { params: { id: A(9201) } }));
  ok("11d opnieuw indienen (uit): 403, niets gewijzigd, geen mail", r.status === 403 && (await tel()) === s0 && mails() === m0, JSON.stringify(r));
  // publieke link
  r = await res(await publicApprove.GET(req("GET"), { params: { token: "tok-fase4" } }));
  ok("L1a publieke link lezen (uit): 404 zonder bongegevens", r.status === 404 && !r.json.receipt, JSON.stringify(r));
  r = await res(await publicApprove.POST(req("POST", { action: "approve", approverName: "T" }), { params: { token: "tok-fase4" } }));
  ok("L1b publieke link goedkeuren (uit): 404, nul schrijfacties", r.status === 404 && (await tel()) === s0, JSON.stringify(r) + ((await tel()) === s0 ? " | NUL schrijfacties" : " | GESCHREVEN"));
  r = await res(await publicApprove.POST(req("POST", { action: "reject", approverName: "T" }), { params: { token: "tok-fase4" } }));
  ok("L1c publieke link afwijzen (uit): 404, nul schrijfacties", r.status === 404 && (await tel()) === s0, JSON.stringify(r));
  r = await res(await publicApprove.POST(req("POST", { action: "approve", approverName: "T" }), { params: { token: "tok-oud" } }));
  ok("L2a oud (afgehandeld) token (uit): 404", r.status === 404 && (await tel()) === s0, JSON.stringify(r));
  r = await res(await publicApprove.GET(req("GET"), { params: { token: "bestaat-niet" } }));
  ok("L3 onbekend token: 404", r.status === 404, JSON.stringify(r));
  // nieuwe bon voor bedrijf met goedkeuring (keuze A)
  const mNieuw = mails(); as("owner");
  r = await res(await newReceipt.POST(req("POST", { lines: [{ description: "Koffie", quantity: 1, unitPrice: 3, vatRate: 9 }] }), { params: { id: A(200) } }));
  const nieuw = r.json.receipt?.id ? await one("select status from receipts where id=$1", [r.json.receipt.id]) : {};
  ok("12a nieuwe bon (goedkeuring uit): aangemaakt, wacht op goedkeuring, geen mail", r.status === 201 && nieuw.status === "pending_approval" && mails() === mNieuw, JSON.stringify(r).slice(0, 200) + JSON.stringify(nieuw));
  ok("12b wachtende bon ongewijzigd na uitzetten", (await one("select status from receipts where id=$1", [A(9201)])).status === "pending_approval"
     && (await one("select status from approvals where id=$1", [A(9202)])).status === "pending");
  const bedrijf = await CompanyDetailPage({ params: { id: A(100) } } as any);
  ok("11e bedrijfspagina (uit): instellingen verborgen, melding zichtbaar", !types(bedrijf).includes("ApprovalSettingsSection") && types(bedrijf).includes("ModuleOff"), types(bedrijf).join(","));
  // fout in de controle bij de publieke link
  await zet("approval", null); cfg.rpcFault = "feature_aan"; s0 = await tel();
  r = await res(await publicApprove.POST(req("POST", { action: "approve", approverName: "T" }), { params: { token: "tok-fase4" } }));
  ok("L4 fout in de featurecontrole (publieke link): 404, nul schrijfacties", r.status === 404 && (await tel()) === s0, JSON.stringify(r));
  cfg.rpcFault = undefined;
  // restaurant uit, module aan
  await q.query("update restaurants set is_active=false where id=$1", [RA]);
  r = await res(await publicApprove.GET(req("GET"), { params: { token: "tok-fase4" } }));
  ok("L7 restaurant uit, module aan: 404", r.status === 404, JSON.stringify(r));
  await q.query("update restaurants set is_active=true where id=$1", [RA]);
  r = await res(await publicApprove.POST(req("POST", { action: "approve", approverName: "T" }), { params: { token: "tok-oud" } }));
  ok("L2b oud token (aan): bestaande melding 'al verwerkt' (400)", r.status === 400 && /al verwerkt/i.test(r.json.error ?? ""), JSON.stringify(r));
  r = await res(await publicApprove.POST(req("POST", { action: "approve", approverName: "T" }), { params: { token: "tok-fase4" } }));
  ok("L6/13c weer aan: hetzelfde token keurt goed (locked)", r.status === 200 && r.json.status === "locked", JSON.stringify(r));
  const bedrijfAan = await CompanyDetailPage({ params: { id: A(100) } } as any);
  ok("13d weer aan: instellingen weer zichtbaar", types(bedrijfAan).includes("ApprovalSettingsSection"));

  // ===== 14. beheer + logboek (platformroute)
  await q.query("insert into platform_admins (user_id) values ($1) on conflict do nothing", [ORPH]);
  as("owner"); r = await res(await moduleRoute.PATCH(req("PATCH", { feature: "approval", enabled: false }), { params: { id: RA } }));
  ok("14a owner A probeert module te wijzigen: 403", r.status === 403 && !(await one("select 1 as x from restaurant_features where restaurant_id=$1 and feature='approval'", [RA])).x, JSON.stringify(r));
  as("admin"); r = await res(await moduleRoute.PATCH(req("PATCH", { feature: "approval", enabled: false }), { params: { id: RA } }));
  const log = await one("select action, restaurant_id, details->>'module' m, admin_user_id from platform_log order by id desc limit 1");
  ok("14b beheerder zet Goedkeuring uit: 200, database uit, logregel module_uit", r.status === 200 && (await one("select enabled from restaurant_features where restaurant_id=$1 and feature='approval'", [RA])).enabled === false
     && log.action === "module_uit" && log.m === "approval" && log.restaurant_id === RA && log.admin_user_id === ORPH, JSON.stringify(r) + JSON.stringify(log));
  r = await res(await restaurantsRoute.GET());
  const ra = (r.json.restaurants ?? []).find((x: any) => x.id === RA); const rb = (r.json.restaurants ?? []).find((x: any) => x.id === RB);
  ok("14c overzicht toont de stand uit de database (A: goedkeuring uit, B: alles aan)", ra?.modules?.find((m: any) => m.key === "approval")?.enabled === false
     && rb?.modules?.every((m: any) => m.enabled === true) && ra?.modules?.length === 3, JSON.stringify(ra?.modules));
  await q.query("alter table platform_log add constraint proef_log_faalt check (false) not valid");
  r = await res(await moduleRoute.PATCH(req("PATCH", { feature: "approval", enabled: true }), { params: { id: RA } }));
  ok("14d logregel faalt: 500 met melding, module blijft uit (atomair)", r.status === 500 && /proef_log_faalt/.test(r.json.error ?? "")
     && (await one("select enabled from restaurant_features where restaurant_id=$1 and feature='approval'", [RA])).enabled === false, JSON.stringify(r));
  await q.query("alter table platform_log drop constraint proef_log_faalt");
  r = await res(await moduleRoute.PATCH(req("PATCH", { feature: "kassa", enabled: true }), { params: { id: RA } }));
  ok("14e onbekende module: 400", r.status === 400, JSON.stringify(r));
  r = await res(await moduleRoute.PATCH(req("PATCH", { feature: "approval", enabled: true }), { params: { id: RA } }));
  ok("14f weer aanzetten via het beheer: 200 + logregel module_aan", r.status === 200 && (await one("select action from platform_log order by id desc limit 1")).action === "module_aan", JSON.stringify(r));

  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
