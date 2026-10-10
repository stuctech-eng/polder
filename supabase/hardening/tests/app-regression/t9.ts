// Fase 2 (migratie 0025, restaurant aan/uit): app-test tegen een lokale database MET 0025.
// Echte permission-service en session-context (requireRole + my_access), twee routes als steekproef en de publieke goedkeuringslink.
// Bouwen: ESBUILD=<pad naar esbuild> node build9.js <repo>; draaien: PGHOST=… PGPORT=… PGUSER=… TESTDB=… NODE_PATH=<node_modules met pg> node t9.js
import { parseAccess, hasAccess, blockedReason, accessMessage } from "@/lib/user-management/access";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { getCurrentUserContext } from "@/lib/user-management/session-context";
import * as companiesRoute from "@/app/api/companies/route";
import * as genInvoice from "@/app/api/open-tabs/[id]/generate-invoice/route";
import * as publicApprove from "@/app/api/public-approve/[token]/route";
// @ts-ignore
import { cfg, end } from "@supabase/supabase-js";
import { Client } from "pg";
process.env.SUPABASE_SERVICE_ROLE_KEY = "service"; process.env.NEXT_PUBLIC_SUPABASE_URL = "x";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const RA = "a0000000-0000-0000-0000-000000000001";
(async () => {
  const q = new Client({ host: process.env.PGHOST || "/home/pgtest", port: +(process.env.PGPORT || 55432), database: process.env.TESTDB || "s3", user: process.env.PGUSER || "pgtest" });
  await q.connect();
  const uid = async (e: string) => (await q.query("select id from auth.users where email=$1", [e])).rows[0].id;
  const U: any = {};
  for (const [k, e] of [["owner", "a.owner@staging.test"], ["adm", "a.admin@staging.test"], ["ina", "a.inactive@staging.test"], ["ownerB", "b.owner@staging.test"]] as const) U[k] = { id: await uid(e) };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const zetA = (aan: boolean) => q.query("update restaurants set is_active=$1 where id=$2", [aan, RA]);
  const one = async (sql: string, p: any[] = []) => (await q.query(sql, p)).rows[0] ?? {};
  const weiger = async (perm: any) => { try { await requireRole(perm); return null; } catch (e: any) { return e instanceof PermissionError ? e : { status: -1, message: String(e) }; } };
  const req = (method: string, body?: any) => new Request("http://x/", { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const res = async (r: Response) => ({ status: r.status, json: await r.json().catch(() => ({})) });
  const tellers = async () => { const x = await one("select (select count(*)::int from invoices) i,(select count(*)::int from domain_events) d,(select count(*)::int from activity_log) l"); return `${x.i}/${x.d}/${x.l}`; };

  // ===== 1. pure functies (geen database)
  ok("parseAccess: 'ok' blijft ok", parseAccess("ok", null) === "ok");
  ok("parseAccess: fout -> onbekend (fail closed)", parseAccess("ok", { message: "x" }) === "onbekend");
  ok("parseAccess: onbekende waarde -> onbekend", parseAccess("misschien", null) === "onbekend" && parseAccess(null, null) === "onbekend");
  ok("hasAccess: alleen ok", ["ok"].every((s) => hasAccess(s as any)) && ["niet_ingelogd", "geen_profiel", "gebruiker_uit", "restaurant_uit", "onbekend"].every((s) => !hasAccess(s as any)));
  ok("blockedReason: gebruiker_uit/restaurant_uit doorsturen, rest niet", blockedReason("gebruiker_uit") === "deactivated" && blockedReason("restaurant_uit") === "restaurant_uit"
     && blockedReason("onbekend") === null && blockedReason("ok") === null && blockedReason("geen_profiel") === null);
  ok("accessMessage: melding voor restaurant uit", /restaurant staat uit/i.test(accessMessage("restaurant_uit") ?? ""));

  // ===== 2. de poort: session-context + requireRole tegen de echte database
  await zetA(true);
  as("owner"); let ctx = await getCurrentUserContext(); ok("A aan: access ok", ctx?.access === "ok" && ctx?.isActive === true, JSON.stringify(ctx));
  ok("A aan: requireRole laat toe", (await weiger("MANAGE_INVOICES")) === null);
  await zetA(false);
  ctx = await getCurrentUserContext(); ok("A uit: access restaurant_uit", ctx?.access === "restaurant_uit" && ctx?.isActive === false, JSON.stringify(ctx));
  let e = await weiger("MANAGE_INVOICES"); ok("A uit: requireRole weigert 403 met melding", e?.status === 403 && /restaurant staat uit/i.test(e?.message ?? ""), JSON.stringify(e));
  as("ownerB"); ok("A uit: owner B nog steeds toegelaten", (await weiger("MANAGE_INVOICES")) === null);
  await zetA(true);
  as("ina"); e = await weiger("MANAGE_RECEIPTS"); ok("gedeactiveerde gebruiker: 403 gedeactiveerd", e?.status === 403 && /gedeactiveerd/i.test(e?.message ?? ""), JSON.stringify(e));
  as("owner"); cfg.rpcFault = "my_access";
  e = await weiger("MANAGE_INVOICES"); ok("fout bij my_access: requireRole weigert (fail closed)", e?.status === 403 && /niet worden gecontroleerd/i.test(e?.message ?? ""), JSON.stringify(e));
  cfg.rpcFault = undefined;
  ok("na herstel van de fout: weer toegelaten", (await weiger("MANAGE_INVOICES")) === null);

  // ===== 3. twee routes als steekproef
  as("owner"); let r = await res(await companiesRoute.GET());
  ok("bedrijven-route, A aan: 200", r.status === 200, JSON.stringify(r));
  await zetA(false); r = await res(await companiesRoute.GET());
  ok("bedrijven-route, A uit: 403", r.status === 403 && /restaurant staat uit/i.test(r.json.error ?? ""), JSON.stringify(r));
  const voor = await tellers();
  as("adm"); r = await res(await (genInvoice as any).POST(req("POST", {}), { params: { id: "a0000000-0000-0000-0000-000000000201" } }));
  ok("factureren, A uit: 403 en nul schrijfacties", r.status === 403 && (await tellers()) === voor, `${JSON.stringify(r)} ${voor} -> ${await tellers()}`);
  await zetA(true);
  r = await res(await (genInvoice as any).POST(req("POST", {}), { params: { id: "a0000000-0000-0000-0000-000000000201" } }));
  ok("factureren, A aan: de poort laat door (geen 403)", r.status !== 403, JSON.stringify(r));

  // ===== 4. publieke goedkeuringslink (service-role, eigen controle)
  const rid = "a0000000-0000-0000-0000-000000009901", aid = "a0000000-0000-0000-0000-000000009902", tok = "tok-fase2-uit";
  await q.query("begin"); await q.query("set local session_replication_role = replica");
  await q.query("insert into receipts (id, restaurant_id, open_tab_id, status, total) values ($1,$2,'a0000000-0000-0000-0000-000000000200','pending_approval',5)", [rid, RA]);
  await q.query("insert into approvals (id, receipt_id, company_id, method, status, verification_code) values ($1,$2,'a0000000-0000-0000-0000-000000000100','qr','pending',$3)", [aid, rid, tok]);
  await q.query("commit");
  const stand = async () => { const x = await one("select (select status from receipts where id=$1) r, (select status from approvals where id=$2) a", [rid, aid]); return `${x.r}/${x.a}/${await tellers()}`; };
  await zetA(false); const s0 = await stand();
  r = await res(await publicApprove.GET(req("GET"), { params: { token: tok } }));
  ok("publieke link lezen, A uit: 404 zonder bongegevens", r.status === 404 && !r.json.receipt, JSON.stringify(r));
  r = await res(await publicApprove.POST(req("POST", { action: "approve", approverName: "Test" }), { params: { token: tok } }));
  ok("publieke link goedkeuren, A uit: 404 en nul schrijfacties", r.status === 404 && (await stand()) === s0, `${JSON.stringify(r)} ${s0} -> ${await stand()}`);
  r = await res(await publicApprove.POST(req("POST", { action: "reject", approverName: "Test" }), { params: { token: tok } }));
  ok("publieke link afwijzen, A uit: 404 en nul schrijfacties", r.status === 404 && (await stand()) === s0, `${JSON.stringify(r)} ${s0} -> ${await stand()}`);
  await zetA(true);
  r = await res(await publicApprove.GET(req("GET"), { params: { token: tok } }));
  ok("publieke link lezen, A aan: 200, zonder restaurant_id in het antwoord", r.status === 200 && !!r.json.receipt && !("restaurant_id" in r.json.receipt), JSON.stringify(r).slice(0, 300));
  r = await res(await publicApprove.POST(req("POST", { action: "approve", approverName: "Test" }), { params: { token: tok } }));
  ok("publieke link goedkeuren, A aan: werkt (locked)", r.status === 200 && r.json.status === "locked", JSON.stringify(r));

  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
