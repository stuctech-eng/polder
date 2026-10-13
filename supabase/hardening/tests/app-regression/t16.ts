// Hardening stap 12 (migratie 0035, PIN-kolommen): app-test. Draait op een database MET 0035 en (zelfde uitkomst) op 0034:
// de nieuwe app leest de PIN alleen nog op de server en werkt dus met de oude en de nieuwe rechten.
// Bouwen: node build16.js <repo>; draaien: PGHOST=… PGPORT=… PGUSER=… TESTDB=… NODE_PATH=… node t16.js
import * as approve from "@/app/api/receipts/[id]/approve/route";
import * as settingsRoute from "@/app/api/companies/[id]/approval-settings/route";
import { getApprovalSettings } from "@/lib/approval/approval-service";
import { hashPin } from "@/lib/approval/providers/pin-provider";
import { createSupabaseServerClient } from "@/lib/supabase/server";
// @ts-ignore
import { cfg, end } from "@supabase/supabase-js";
import { Client } from "pg";
process.env.SUPABASE_SERVICE_ROLE_KEY = "service"; process.env.NEXT_PUBLIC_SUPABASE_URL = "x"; process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "anon";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const RA = "a0000000-0000-0000-0000-000000000001";
const A = (n: number) => `a0000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
const B = (n: number) => `b0000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
(async () => {
  const q = new Client({ host: process.env.PGHOST, port: +(process.env.PGPORT || 55432), database: process.env.TESTDB, user: process.env.PGUSER });
  await q.connect();
  const one = async (sql: string, p: any[] = []) => (await q.query(sql, p)).rows[0] ?? {};
  const uid = async (e: string) => (await one("select id from auth.users where email=$1", [e])).id;
  const U: any = { admin: { id: await uid("a.admin@staging.test") }, mgr: { id: await uid("a.manager@staging.test") },
                   bed: { id: await uid("a.bediening@staging.test") } };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const req = (method: string, body?: any) => new Request("http://x/", { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const teksten: string[] = [];
  const res = async (r: Response) => { const t = await r.text(); teksten.push(t); let json: any = {}; try { json = JSON.parse(t); } catch {} return { status: r.status, json }; };
  const status = async (id: string) => (await one("select status from receipts where id=$1", [id])).status;
  const pinRij = async (c: string) => JSON.stringify(await one("select is_required, method, auto_lock, pin_hash, pin_salt, notify_email from approval_settings where company_id=$1", [c]));
  const svcLeest = () => ((cfg.reads ?? []) as any[]).filter((r) => r.role === "service_role" && r.table === "approval_settings").length;

  // opzet (als postgres): bedrijf 100 met PIN 1234; bedrijf 105 met methode PIN maar zonder PIN; wachtende bonnen
  const p1 = hashPin("1234");
  await q.query("set session_replication_role = replica");
  await q.query("delete from approval_settings where company_id in ($1,$2)", [A(100), A(105)]);
  await q.query("insert into approval_settings (company_id, method, is_required, auto_lock, pin_hash, pin_salt) values ($1,'pin',true,true,$2,$3)", [A(100), p1.hash, p1.salt]);
  await q.query("insert into approval_settings (company_id, method, is_required, auto_lock) values ($1,'pin',true,true)", [A(105)]);
  await q.query("insert into open_tabs (id, restaurant_id, company_id, status) values ($1,$2,$3,'open') on conflict do nothing", [A(9300), RA, A(105)]);
  const bon = async (n: number, tab: string, comp: string) => {
    await q.query("insert into receipts (id, restaurant_id, open_tab_id, status, total) values ($1,$2,$3,'pending_approval',5)", [A(n), RA, tab]);
    await q.query("insert into approvals (receipt_id, company_id, method, status) values ($1,$2,'pin','pending')", [A(n), comp]);
    return A(n);
  };
  const b1 = await bon(9301, A(200), A(100)), b2 = await bon(9302, A(200), A(100)), b3 = await bon(9303, A(200), A(100));
  const b4 = await bon(9304, A(9300), A(105)), b5 = await bon(9305, A(200), A(100));
  await q.query("set session_replication_role = origin");
  const approveAls = async (k: string, id: string, credential?: string) => { as(k); return res(await approve.POST(req("POST", { credential }), { params: { id } })); };

  // ===== 1. getApprovalSettings leest geen PIN meer (en werkt dus ook onder 0035, als bediening)
  as("bed"); cfg.reads = [];
  const st: any = await getApprovalSettings(createSupabaseServerClient(), A(100));
  ok("1 getApprovalSettings (bediening): methode pin, aan; geen pinHash/pinSalt in het resultaat",
     st.enabled === true && st.method === "pin" && !("pinHash" in st) && !("pinSalt" in st), JSON.stringify(st));
  ok("2 getApprovalSettings vraagt geen pin_hash/pin_salt op", ((cfg.reads ?? []) as any[]).every((r) => !/pin_/.test(r.cols)), JSON.stringify(cfg.reads));

  // ===== 2. goedkeuren met PIN (manager heeft APPROVE_RECEIPTS)
  let r = await approveAls("mgr", b1, "0000");
  ok("3 onjuiste PIN: 400 'Onjuiste PIN', bon blijft wachten", r.status === 400 && /Onjuiste PIN/.test(r.json.error ?? "") && (await status(b1)) === "pending_approval", JSON.stringify(r));
  r = await approveAls("mgr", b1, "1234");
  ok("4 juiste PIN: 200, bon vergrendeld", r.status === 200 && (await status(b1)) === "locked", JSON.stringify(r));
  r = await approveAls("mgr", b4, "1234");
  ok("5 bedrijf zonder ingestelde PIN: 400 'nog geen PIN ingesteld'", r.status === 400 && /nog geen PIN/.test(r.json.error ?? "") && (await status(b4)) === "pending_approval", JSON.stringify(r));

  // ===== 3. volgorde: geen rol -> geen serverlezing
  cfg.reads = [];
  r = await approveAls("bed", b2, "1234");
  ok("6 bediening keurt goed: 403, en de server heeft de PIN NIET gelezen", r.status === 403 && svcLeest() === 0 && (await status(b2)) === "pending_approval", `${JSON.stringify(r)} reads=${svcLeest()}`);
  cfg.reads = [];
  r = await approveAls("mgr", b1 /* al vergrendeld in test 4: wacht niet meer */, "1234");
  ok("7 bon die niet wacht: 400, en de server heeft de PIN NIET gelezen", r.status === 400 && svcLeest() === 0, `${JSON.stringify(r)} reads=${svcLeest()}`);
  cfg.reads = [];
  r = await approveAls("mgr", B(301), "1234");
  ok("8 bon van restaurant B: 404, en de server heeft de PIN NIET gelezen", r.status === 404 && svcLeest() === 0, `${JSON.stringify(r)} reads=${svcLeest()}`);

  // ===== 4. fail closed in de goedkeurroute
  cfg.fault = { table: "approval_settings", role: "service_role", mode: "error" };
  r = await approveAls("mgr", b2, "1234");
  ok("9 serverlezing faalt: 500 met de vaste melding, bon blijft wachten (nooit goedgekeurd)",
     r.status === 500 && r.json.error === "PIN-controle is nu niet mogelijk, probeer het opnieuw" && (await status(b2)) === "pending_approval", JSON.stringify(r));
  cfg.fault = { table: "approval_settings", role: "service_role", mode: "throw" };
  r = await approveAls("mgr", b2, "1234");
  ok("10 serverlezing gooit een fout: zelfde vaste melding, bon blijft wachten", r.status === 500 && r.json.error === "PIN-controle is nu niet mogelijk, probeer het opnieuw" && (await status(b2)) === "pending_approval", JSON.stringify(r));
  cfg.fault = undefined;

  // ===== 5. instellingenroute
  as("admin");
  const put = async (c: string, body: any) => res(await settingsRoute.PUT(req("PUT", body), { params: { id: c } }));
  r = await put(A(100), { enabled: true, method: "pin", autoLock: true });
  ok("11 PIN bestaat al, opslaan zonder nieuwe PIN: 200", r.status === 200, JSON.stringify(r));
  let voor = await pinRij(A(105));
  r = await put(A(105), { enabled: true, method: "pin", autoLock: true });
  ok("12 nog geen PIN: 400 'Stel eerst een PIN in', niets gewijzigd", r.status === 400 && /Stel eerst een PIN in/.test(r.json.error ?? "") && (await pinRij(A(105))) === voor, JSON.stringify(r));
  voor = await pinRij(A(100));
  cfg.fault = { table: "approval_settings", role: "service_role", mode: "error" };
  r = await put(A(100), { enabled: true, method: "pin", autoLock: false });
  cfg.fault = undefined;
  ok("13 PIN-status-lezing faalt: 500 met de vaste melding, niets opgeslagen (nooit 'geen PIN' aangenomen)",
     r.status === 500 && r.json.error === "PIN-status kon niet worden gecontroleerd" && (await pinRij(A(100))) === voor, JSON.stringify(r));
  r = await put(A(100), { enabled: true, method: "pin", autoLock: true, newPin: "5678" });
  ok("14 nieuwe PIN instellen: 200", r.status === 200, JSON.stringify(r));
  r = await approveAls("mgr", b3, "1234");
  ok("15 oude PIN werkt niet meer", r.status === 400 && (await status(b3)) === "pending_approval", JSON.stringify(r));
  r = await approveAls("mgr", b3, "5678");
  ok("16 nieuwe PIN werkt", r.status === 200 && (await status(b3)) === "locked", JSON.stringify(r));
  as("admin"); cfg.reads = [];
  r = await put(B(100), { enabled: true, method: "pin", autoLock: true });
  ok("17 bedrijf van restaurant B: 404 'Bedrijf niet gevonden', en de server heeft de PIN NIET gelezen", r.status === 404 && svcLeest() === 0, `${JSON.stringify(r)} reads=${svcLeest()}`);
  as("mgr"); cfg.reads = [];
  r = await res(await settingsRoute.PUT(req("PUT", { enabled: true, method: "pin", autoLock: true, newPin: "9999" }), { params: { id: A(100) } }));
  ok("18 manager wijzigt PIN: 403, niets gelezen", r.status === 403 && svcLeest() === 0, JSON.stringify(r));
  as("admin");
  r = await res(await settingsRoute.GET(req("GET"), { params: { id: A(100) } }));
  ok("19 GET instellingen: 200 zonder PIN-velden", r.status === 200 && r.json.settings && !("pinHash" in r.json.settings) && !("pin_hash" in r.json.settings), JSON.stringify(r));

  // ===== 6. nergens PIN-gegevens in een response
  const nu = await one("select pin_hash, pin_salt from approval_settings where company_id=$1", [A(100)]);
  const geheim = [p1.hash, p1.salt, nu.pin_hash, nu.pin_salt].filter(Boolean);
  const lek = teksten.filter((t) => geheim.some((g: string) => t.includes(g)) || /pin_hash|pin_salt|pinHash|pinSalt/.test(t));
  ok(`20 geen enkele response (${teksten.length}) bevat hash, salt of de veldnamen`, lek.length === 0, lek.join(" || ").slice(0, 300));
  void b5;

  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
