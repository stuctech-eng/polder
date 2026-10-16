// Stap 14a fase B (migraties 0041 bon_indienen + 0042 wacht op de bon): app-test van de PIN-pogingen, de methode per bon
// en het indienen in een keer. Draait op een database MET 0042 (alles) en ook op 0041 (zonder de wacht): dan is precies
// test 9 (de 2-minutengrens, die alleen de database afdwingt) anders. Bouwen: node build17.js <repo>;
// draaien: PGHOST=… PGPORT=… PGUSER=… TESTDB=… NODE_PATH=… node t17.js
import * as approve from "@/app/api/receipts/[id]/approve/route";
import * as settingsRoute from "@/app/api/companies/[id]/approval-settings/route";
import * as requestApproval from "@/app/api/receipts/[id]/request-approval/route";
import * as newReceipt from "@/app/api/open-tabs/[id]/receipts/route";
import OpenTabDetailPage from "@/app/(dashboard)/open-tabs/[id]/page";
import { methodForReceipt, CONFLICTING_RULES, ADMIN_INCOMPLETE_WARNING } from "@/lib/approval/approval-method";
import { hashPin } from "@/lib/approval/providers/pin-provider";
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
(async () => {
  const q = new Client({ host: process.env.PGHOST, port: +(process.env.PGPORT || 55432), database: process.env.TESTDB, user: process.env.PGUSER });
  await q.connect();
  const one = async (sql: string, p: any[] = []) => (await q.query(sql, p)).rows[0] ?? {};
  const uid = async (e: string) => (await one("select id from auth.users where email=$1", [e])).id;
  const U: any = { owner: { id: await uid("a.owner@staging.test") }, admin: { id: await uid("a.admin@staging.test") },
                   mgr: { id: await uid("a.manager@staging.test") }, bed: { id: await uid("a.bediening@staging.test") } };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const req = (method: string, body?: any) => new Request("http://x/", { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const teksten: string[] = [];
  const res = async (r: Response) => { const t = await r.text(); teksten.push(t); let json: any = {}; try { json = JSON.parse(t); } catch {} return { status: r.status, json }; };
  const status = async (id: string) => (await one("select status from receipts where id=$1", [id])).status;
  const regels = async (id: string) => (await one("select count(*)::int n, string_agg(method || ':' || status, ',' order by method) s from approvals where receipt_id=$1", [id]));
  const reserv = async (id: string) => (await one("select count(*)::int n, count(*) filter (where verbruikt_op is not null)::int v from pin_reserveringen where receipt_id=$1", [id]));
  const events = async (id: string) => (await one("select count(*)::int n from domain_events where event_type='ApprovalCompleted' and payload->>'receipt_id'=$1", [id])).n;
  const logs = async (id: string) => (await one("select count(*)::int n from activity_log where target_id=$1 and action like 'keurde een bon goed%'", [id])).n;
  const svcLeest = () => ((cfg.reads ?? []) as any[]).filter((r) => r.role === "service_role" && r.table === "approval_settings").length;
  const wacht = (await one("select count(*)::int n from pg_trigger where tgname='receipts_pin_wacht'")).n === 1;
  const approveAls = async (k: string, id: string, credential?: string) => { as(k); return res(await approve.POST(req("POST", { credential }), { params: { id } })); };

  // ===== opzet (als postgres). Bedrijven in restaurant A: 100 = PIN 1234; 9400 = PIN 2468 (tweede PIN-bedrijf);
  // 9500 = restaurant_confirms, maar met een oude PIN 1357; 9600 = QR. Tabbladen per bedrijf, bonnen met regel naar keuze.
  const p100 = hashPin("1234"), p94 = hashPin("2468"), p95 = hashPin("1357");
  await q.query("set session_replication_role = replica");
  for (const [c, n] of [[9400, "PIN twee"], [9500, "Restaurant bevestigt"], [9600, "QR bedrijf"]] as const) {
    await q.query("insert into companies (id, restaurant_id, name) values ($1,$2,$3) on conflict do nothing", [A(c), RA, n]);
    await q.query("insert into open_tabs (id, restaurant_id, company_id, status) values ($1,$2,$3,'open') on conflict do nothing", [A(c + 1), RA, A(c)]);
  }
  await q.query("delete from approval_settings where company_id in ($1,$2,$3,$4)", [A(100), A(9400), A(9500), A(9600)]);
  await q.query("insert into approval_settings (company_id, method, is_required, auto_lock, pin_hash, pin_salt) values ($1,'pin',true,true,$2,$3), ($4,'pin',true,true,$5,$6), ($7,'restaurant_confirms',true,true,$8,$9), ($10,'qr',true,true,null,null)",
    [A(100), p100.hash, p100.salt, A(9400), p94.hash, p94.salt, A(9500), p95.hash, p95.salt, A(9600)]);
  const bon = async (n: number, tab: string, regelsVan: [string, string][], st = "pending_approval") => {
    await q.query("insert into receipts (id, restaurant_id, open_tab_id, status, total) values ($1,$2,$3,$4,5)", [A(n), RA, tab, st]);
    for (const [comp, m] of regelsVan) await q.query("insert into approvals (receipt_id, company_id, method, status, verification_code) values ($1,$2,$3,'pending',$4)", [A(n), comp, m, m === "qr" ? "tok-" + n : null]);
    return A(n);
  };
  const pinBon = (n: number) => bon(n, A(200), [[A(100), "pin"]]);
  const k1 = await pinBon(9701), k2 = await pinBon(9702), k3 = await pinBon(9703), k4 = await pinBon(9704), k5 = await pinBon(9705), k6 = await pinBon(9706);
  const k7 = await pinBon(9707), k8 = await pinBon(9708);
  const t2 = await bon(9711, A(9401), [[A(9400), "pin"]]);
  const qrBijPin = await bon(9712, A(200), [[A(100), "qr"]]);                 // QR-regel, bedrijf staat nu op PIN
  const pinBijRc = await bon(9713, A(9501), [[A(9500), "pin"]]);              // PIN-regel, bedrijf staat nu op restaurant_confirms
  const rcRegel = await bon(9714, A(9501), [[A(9500), "restaurant_confirms"]]);
  const conflict = await bon(9715, A(200), [[A(100), "pin"], [A(100), "qr"]]);
  const zonderRegel = await bon(9716, A(200), []);                            // geen regel: bedrijfsinstelling (PIN) geldt
  const indien1 = await bon(9717, A(200), [], "linked"), indien2 = await bon(9718, A(9601), [], "linked"), indien3 = await bon(9719, A(200), [], "linked");
  await q.query("set session_replication_role = origin");

  // ===== 1. gedeelde regel (zelfde als database pin_eis)
  const r0 = methodForReceipt([{ method: "qr", company_id: "c1", status: "pending" }, { method: "pin", company_id: "c2", status: "approved" }], "c3", "pin");
  ok("1 methode per bon: wachtende regel wint (qr, bedrijf van de regel); afgehandelde regels tellen niet", r0.ok && r0.method === "qr" && r0.companyId === "c1", JSON.stringify(r0));
  const r1 = methodForReceipt([], "c3", "pin"), r2 = methodForReceipt([{ method: "pin", company_id: "c1", status: "pending" }, { method: "qr", company_id: "c1", status: "pending" }], "c1", "pin");
  ok("2 geen regel: bedrijfsinstelling; tegenstrijdige regels: weigeren", r1.ok && r1.method === "pin" && r1.companyId === "c3" && !r2.ok, JSON.stringify([r1, r2]));

  // ===== 2. juiste PIN
  let r = await approveAls("mgr", k1, "1234");
  let rv = await reserv(k1);
  ok("3 juiste PIN: 200, bon vergrendeld, regel goedgekeurd, 1 reservering verbruikt, 1 event, 1 logregel, geen waarschuwing",
     r.status === 200 && (await status(k1)) === "locked" && (await regels(k1)).s === "pin:approved" && rv.n === 1 && rv.v === (wacht ? 1 : 0)
     && (await events(k1)) === 1 && (await logs(k1)) === 1 && r.json.warning === null, JSON.stringify([r, rv]));
  r = await approveAls("mgr", k1, "1234");
  ok("4 nog eens (bon wacht niet meer): 400, geen nieuwe reservering", r.status === 400 && (await reserv(k1)).n === 1, JSON.stringify(r));

  // ===== 3. onjuiste PIN en blokkade (per bedrijf)
  const fouten: any[] = [];
  for (let i = 0; i < 5; i++) fouten.push(await approveAls("mgr", k2, "0000"));
  ok("5 onjuiste PIN 1-4: 400 met het aantal resterende pogingen (4,3,2,1)",
     [0, 1, 2, 3].every((i) => fouten[i].status === 400 && fouten[i].json.error === `Onjuiste PIN. Nog ${4 - i} ${4 - i === 1 ? "poging" : "pogingen"}.`), JSON.stringify(fouten.slice(0, 4).map((x) => x.json.error)));
  ok("6 onjuiste PIN 5: 400 'geblokkeerd tot HH:MM'", fouten[4].status === 400 && /^Onjuiste PIN\. Te veel onjuiste pogingen: geblokkeerd tot \d\d:\d\d\.$/.test(fouten[4].json.error), JSON.stringify(fouten[4]));
  cfg.reads = [];
  r = await approveAls("mgr", k3, "1234");
  ok("7 tijdens de blokkade, ook met de juiste PIN: 429 met tijd, bon wacht, de PIN-hash is NIET gelezen",
     r.status === 429 && /geblokkeerd tot \d\d:\d\d/.test(r.json.error ?? "") && (await status(k3)) === "pending_approval" && svcLeest() === 0, `${JSON.stringify(r)} reads=${svcLeest()}`);
  r = await approveAls("mgr", t2, "2468");
  ok("8 ander PIN-bedrijf heeft geen last van de blokkade: 200", r.status === 200 && (await status(t2)) === "locked", JSON.stringify(r));

  // ===== 4. PIN-wijziging heft de blokkade op; wijziging tijdens de poging = verlopen
  as("admin");
  r = await res(await settingsRoute.PUT(req("PUT", { enabled: true, method: "pin", autoLock: true, newPin: "4321" }), { params: { id: A(100) } }));
  ok("9a nieuwe PIN via de instellingen: 200", r.status === 200, JSON.stringify(r));
  r = await approveAls("mgr", k3, "4321");
  ok("9b na de PIN-wijziging is de blokkade weg: nieuwe PIN keurt goed", r.status === 200 && (await status(k3)) === "locked", JSON.stringify(r));
  cfg.hook = async (soort: string, naam: string) => { if (soort === "rpc" && naam === "pin_poging_afronden") { cfg.hook = undefined;
    const h = hashPin("8642"); await q.query("update approval_settings set pin_hash=$1, pin_salt=$2 where company_id=$3", [h.hash, h.salt, A(100)]); } };
  r = await approveAls("mgr", k4, "4321");
  ok("10 PIN gewijzigd tussen reserveren en afronden: 409 'net gewijzigd', bon wacht", r.status === 409 && /net gewijzigd/.test(r.json.error ?? "") && (await status(k4)) === "pending_approval", JSON.stringify(r));
  r = await approveAls("mgr", k4, "8642");
  ok("11 daarna met de nieuwe PIN: 200", r.status === 200 && (await status(k4)) === "locked", JSON.stringify(r));

  // ===== 5. 2-minutengrens (alleen de database dwingt die af: 0042)
  cfg.hook = async (soort: string, naam: string) => { if (soort === "update" && naam === "receipts") { cfg.hook = undefined;
    await q.query("update pin_reserveringen set afgerond_op = clock_timestamp() - interval '121 seconds' where receipt_id=$1", [k5]); } };
  r = await approveAls("mgr", k5, "8642");
  ok("12 juiste PIN, maar ouder dan 2 minuten bij het goedkeuren: 409 'opnieuw', bon wacht (database 0042)",
     r.status === 409 && /Voer de PIN opnieuw in/.test(r.json.error ?? "") && (await status(k5)) === "pending_approval", JSON.stringify(r));
  cfg.hook = undefined;

  // ===== 6. dubbel verzoek: het tweede komt binnen terwijl het eerste net wil goedkeuren
  let binnen: any = null;
  cfg.hook = async (soort: string, naam: string) => { if (soort === "update" && naam === "receipts") { cfg.hook = undefined; binnen = await approveAls("mgr", k6, "8642"); } };
  r = await approveAls("mgr", k6, "8642");
  ok("13 dubbel verzoek: precies een keer goedgekeurd (200 + 409 'al afgehandeld'), 1 event, 1 logregel",
     binnen?.status === 200 && r.status === 409 && /al afgehandeld/.test(r.json.error ?? "") && (await status(k6)) === "locked" && (await events(k6)) === 1 && (await logs(k6)) === 1,
     JSON.stringify([binnen, r]));

  // ===== 7. methode per bon
  r = await approveAls("mgr", qrBijPin, "8642");
  ok("14 QR-regel bij een bedrijf dat nu op PIN staat: geen PIN-weg (400 'niet via dit kanaal'), geen reservering, bon wacht",
     r.status === 400 && /niet via dit kanaal/.test(r.json.error ?? "") && (await reserv(qrBijPin)).n === 0 && (await status(qrBijPin)) === "pending_approval", JSON.stringify(r));
  r = await approveAls("mgr", pinBijRc);
  ok("15a PIN-regel bij een bedrijf dat nu op restaurant_confirms staat: zonder PIN 400 'PIN is verplicht'", r.status === 400 && r.json.error === "PIN is verplicht" && (await status(pinBijRc)) === "pending_approval", JSON.stringify(r));
  r = await approveAls("mgr", pinBijRc, "1357");
  ok("15b ... met de PIN van dat bedrijf: 200", r.status === 200 && (await status(pinBijRc)) === "locked", JSON.stringify(r));
  r = await approveAls("mgr", rcRegel);
  ok("16 restaurant_confirms-regel: 200 zonder PIN, geen reservering", r.status === 200 && (await status(rcRegel)) === "locked" && (await reserv(rcRegel)).n === 0, JSON.stringify(r));
  r = await approveAls("mgr", conflict, "8642");
  ok("17 tegenstrijdige wachtende regels: 409 met duidelijke melding, geen reservering", r.status === 409 && r.json.error === CONFLICTING_RULES && (await reserv(conflict)).n === 0, JSON.stringify(r));
  r = await approveAls("mgr", zonderRegel);
  ok("18 geen regel, bedrijf op PIN: PIN verplicht", r.status === 400 && r.json.error === "PIN is verplicht", JSON.stringify(r));
  as("owner");
  const pagina = await OpenTabDetailPage({ params: { id: A(200) } });
  let bonnen: any[] = []; walk(pagina, (e) => { if (Array.isArray(e.props?.initialReceipts)) bonnen = e.props.initialReceipts; });
  const vb = (id: string) => bonnen.find((b) => b.id === id) ?? {};
  ok("19 scherm: per bon de methode van de regel (qr bij PIN-bedrijf), PIN zonder regel, tegenstrijdig = melding i.p.v. knop",
     vb(qrBijPin).approval_method === "qr" && vb(zonderRegel).approval_method === "pin" && vb(k7).approval_method === "pin"
     && vb(conflict).approval_conflict === CONFLICTING_RULES && vb(k7).approval_conflict === null, JSON.stringify(bonnen.map((b) => [b.id.slice(-4), b.approval_method, b.approval_conflict])));

  // ===== 8. fail closed
  cfg.rpcFault = "pin_poging_start"; r = await approveAls("mgr", k7, "8642"); cfg.rpcFault = undefined;
  ok("20 reserveren faalt: 500 vaste melding, bon wacht", r.status === 500 && r.json.error === "PIN-controle is nu niet mogelijk, probeer het opnieuw" && (await status(k7)) === "pending_approval", JSON.stringify(r));
  cfg.rpcFault = "pin_poging_afronden"; r = await approveAls("mgr", k7, "8642"); cfg.rpcFault = undefined;
  ok("21 afronden faalt: 500 vaste melding, bon wacht", r.status === 500 && r.json.error === "PIN-controle is nu niet mogelijk, probeer het opnieuw" && (await status(k7)) === "pending_approval", JSON.stringify(r));
  cfg.fault = { table: "approval_settings", role: "service_role", mode: "throw" }; r = await approveAls("mgr", k7, "8642"); cfg.fault = undefined;
  ok("22 PIN lezen faalt: 500 vaste melding, bon wacht", r.status === 500 && r.json.error === "PIN-controle is nu niet mogelijk, probeer het opnieuw" && (await status(k7)) === "pending_approval", JSON.stringify(r));
  cfg.fault = { table: "approvals", mode: "error" }; r = await approveAls("mgr", k7, "8642"); cfg.fault = undefined;
  ok("23 regels lezen faalt: 500, geen reservering", r.status === 500 && (await reserv(k7)).n === 2 && (await status(k7)) === "pending_approval", JSON.stringify(r));
  cfg.reads = [];
  r = await approveAls("bed", k7, "8642");
  ok("24 bediening: 403, geen reservering, PIN niet gelezen", r.status === 403 && (await reserv(k7)).n === 2 && svcLeest() === 0, JSON.stringify(r));

  // ===== 9. goedgekeurd, maar de regel kan niet worden bijgewerkt: 200 met waarschuwing
  cfg.writeFault = "approvals"; r = await approveAls("mgr", k8, "8642"); cfg.writeFault = undefined;
  ok("25 regel bijwerken faalt na goedkeuring: 200 MET waarschuwing, bon vergrendeld, regel nog pending",
     r.status === 200 && r.json.warning === ADMIN_INCOMPLETE_WARNING && (await status(k8)) === "locked" && (await regels(k8)).s === "pin:pending", JSON.stringify(r));
  as("owner");
  let na: any[] = []; walk(await OpenTabDetailPage({ params: { id: A(200) } }), (e) => { if (Array.isArray(e.props?.initialReceipts)) na = e.props.initialReceipts; });
  const vn = (id: string) => na.find((b) => b.id === id) ?? {};
  ok("25b scherm na herladen/verversen: de waarschuwing komt uit de database en blijft staan (k8); volledig afgehandelde bon zonder (k1)",
     vn(k8).approval_warning === ADMIN_INCOMPLETE_WARNING && vn(k1).approval_warning === null, JSON.stringify([vn(k8).approval_warning, vn(k1).approval_warning]));

  // ===== 10. indienen in een keer
  as("mgr");
  r = await res(await requestApproval.POST(req("POST"), { params: { id: indien1 } }));
  ok("26 aanvragen (PIN-bedrijf): 200, bon wacht, precies 1 PIN-regel, geen token", r.status === 200 && r.json.method === "pin" && r.json.approvalToken === null
     && (await status(indien1)) === "pending_approval" && (await regels(indien1)).s === "pin:pending", JSON.stringify(r));
  r = await res(await requestApproval.POST(req("POST"), { params: { id: indien2 } }));
  const tok = (await one("select verification_code from approvals where receipt_id=$1", [indien2])).verification_code;
  ok("27 aanvragen (QR-bedrijf): token terug en bewaard", r.status === 200 && r.json.method === "qr" && typeof r.json.approvalToken === "string" && r.json.approvalToken === tok, JSON.stringify(r));
  await q.query("create function public.tmp_wijkt_af() returns trigger language plpgsql as $$ begin raise exception 'Methode wijkt af van de bedrijfsinstelling'; end $$");
  await q.query("create trigger zz_tmp_wijkt_af before insert on public.approvals for each row execute function public.tmp_wijkt_af()");
  r = await res(await requestApproval.POST(req("POST"), { params: { id: indien3 } }));
  ok("28 instelling net gewijzigd (regel geweigerd): 409 'opnieuw', bon blijft linked, geen regel (alles of niets)",
     r.status === 409 && /net gewijzigd/.test(r.json.error ?? "") && (await status(indien3)) === "linked" && (await regels(indien3)).n === 0, JSON.stringify(r));
  r = await res(await newReceipt.POST(req("POST", { lines: [{ description: "Koffie", quantity: 1, unitPrice: 3, vatRate: 9 }] }), { params: { id: A(200) } }));
  const nieuw = r.json.receipt?.id;
  ok("29 nieuwe bon terwijl indienen faalt: 201, bon gekoppeld (niet wachtend), waarschuwing zichtbaar, geen regel",
     r.status === 201 && (await status(nieuw)) === "linked" && /Goedkeuring is niet aangevraagd/.test(r.json.approvalWarning ?? "") && (await regels(nieuw)).n === 0, JSON.stringify(r).slice(0, 300));
  await q.query("drop trigger zz_tmp_wijkt_af on public.approvals; drop function public.tmp_wijkt_af()");
  r = await res(await newReceipt.POST(req("POST", { lines: [{ description: "Thee", quantity: 1, unitPrice: 3, vatRate: 9 }] }), { params: { id: A(200) } }));
  const nieuw2 = r.json.receipt?.id;
  ok("30 nieuwe bon (PIN-bedrijf): 201, wacht, 1 PIN-regel", r.status === 201 && (await status(nieuw2)) === "pending_approval" && (await regels(nieuw2)).s === "pin:pending", JSON.stringify(r).slice(0, 300));
  r = await approveAls("mgr", nieuw2, "8642");
  ok("31 en die bon met PIN goedkeuren: 200", r.status === 200 && (await status(nieuw2)) === "locked", JSON.stringify(r));

  // ===== 11. nergens PIN-gegevens in een response
  const geheim = (await q.query("select pin_hash, pin_salt from approval_settings where pin_hash is not null")).rows.flatMap((x: any) => [x.pin_hash, x.pin_salt])
    .concat([p100.hash, p100.salt, p94.hash, p95.hash]);
  const lek = teksten.filter((t) => geheim.some((g: string) => t.includes(g)) || /pin_hash|pin_salt|pinHash|pinSalt/.test(t));
  ok(`32 geen enkele response (${teksten.length}) bevat hash, salt of de veldnamen`, lek.length === 0, lek.join(" || ").slice(0, 300));

  console.log(`database: ${wacht ? "MET" : "ZONDER"} wacht op de bon (0042)`);
  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
