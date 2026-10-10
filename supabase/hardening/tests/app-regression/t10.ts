// Platformbeheer (migratie 0026): app-test tegen een lokale database MET 0026.
// Echte platform-access, platform-service, team-service (inviteProfile) en de platformroutes; alleen de Supabase-clients zijn gestubd.
// Bouwen: ESBUILD=<pad naar esbuild> node build10.js <repo>; draaien: PGHOST=… PGPORT=… PGUSER=… TESTDB=… NODE_PATH=<node_modules met pg> node t10.js
import { isPlatformAdmin, requirePlatformAdmin } from "@/lib/platform/platform-access";
import { PermissionError, requireRole } from "@/lib/user-management/permission-service";
import * as restaurantsRoute from "@/app/api/platform/restaurants/route";
import * as restaurantRoute from "@/app/api/platform/restaurants/[id]/route";
import * as ownerRoute from "@/app/api/platform/restaurants/[id]/owner/route";
import * as logRoute from "@/app/api/platform/log/route";
import * as companiesRoute from "@/app/api/companies/route";
import * as teamRoute from "@/app/api/team/route";
// @ts-ignore
import { cfg, end } from "@supabase/supabase-js";
import { Client } from "pg";
process.env.SUPABASE_SERVICE_ROLE_KEY = "service"; process.env.NEXT_PUBLIC_SUPABASE_URL = "x";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const RA = "a0000000-0000-0000-0000-000000000001", ORPH = "c0000000-0000-0000-0000-000000000001", ONBEKEND = "e0000000-0000-0000-0000-000000000099";
(async () => {
  const q = new Client({ host: process.env.PGHOST || "/home/pgtest", port: +(process.env.PGPORT || 55432), database: process.env.TESTDB || "s3", user: process.env.PGUSER || "pgtest" });
  await q.connect();
  const one = async (sql: string, p: any[] = []) => (await q.query(sql, p)).rows[0] ?? {};
  const uid = async (e: string) => (await one("select id from auth.users where email=$1", [e])).id;
  const U: any = { anon: { id: "" }, owner: { id: await uid("a.owner@staging.test") }, admin: { id: ORPH } };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const req = (method: string, body?: any) => new Request("http://x/", { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const res = async (r: Response) => ({ status: r.status, json: await r.json().catch(() => ({})) });
  const stand = async () => { const x = await one("select (select count(*)::int from restaurants) r, (select count(*) filter (where is_active)::int from restaurants) a, (select count(*)::int from platform_log) l, (select count(*)::int from users) u, (select count(*)::int from auth.users) au"); return `${x.r}/${x.a}/${x.l}/${x.u}/${x.au}`; };
  const alle = async () => {
    const id = { params: { id: RA } };
    return [await res(await restaurantsRoute.GET()), await res(await restaurantsRoute.POST(req("POST", { name: "X" }))),
      await res(await restaurantRoute.PATCH(req("PATCH", { isActive: false }), id)),
      await res(await ownerRoute.POST(req("POST", { email: "x@staging.test", fullName: "X" }), id)), await res(await logRoute.GET())];
  };
  const isA = async () => (await one("select is_active from restaurants where id=$1", [RA])).is_active;
  const laatste = async () => (await one("select action, restaurant_id, admin_user_id, details from platform_log order by id desc limit 1"));

  // ===== 1. geen beheerder: elke route weigert, niets gewijzigd
  for (const [wie, code] of [["anon", 401], ["owner", 403], ["admin", 403]] as const) {
    as(wie); const s0 = await stand(); const r = await alle();
    ok(`${wie} (geen beheerder): alle 5 platformroutes ${code}, niets gewijzigd`, r.every((x) => x.status === code) && (await stand()) === s0, JSON.stringify(r.map((x) => x.status)) + ` ${s0} -> ${await stand()}`);
  }
  as("admin"); ok("isPlatformAdmin onwaar zolang hij niet in de lijst staat", (await isPlatformAdmin()) === false);

  // ===== 2. beheerder (alleen met SQL toe te voegen)
  await q.query("insert into platform_admins (user_id) values ($1)", [ORPH]);
  ok("isPlatformAdmin waar voor beheerder", (await isPlatformAdmin()) === true);
  let r = await res(await restaurantsRoute.GET());
  const lijst = r.json.restaurants ?? [];
  const a = lijst.find((x: any) => x.id === RA);
  ok("overzicht: 200 met restaurant A, eigenaar met e-mail en aantal gebruikers", r.status === 200 && !!a && a.userCount > 0 && a.owners.some((o: any) => o.email === "a.owner@staging.test"), JSON.stringify(r).slice(0, 300));
  ok("overzicht: alleen platformvelden (geen facturen, bonnen of bedragen)", lijst.every((x: any) => Object.keys(x).sort().join() === "createdAt,id,isActive,name,owners,userCount"), JSON.stringify(Object.keys(a ?? {})));

  // aanmaken
  let s0 = await stand();
  r = await res(await restaurantsRoute.POST(req("POST", { name: "  " })));
  ok("aanmaken zonder naam: 400 en niets gewijzigd", r.status === 400 && (await stand()) === s0, JSON.stringify(r));
  r = await res(await restaurantsRoute.POST(req("POST", { name: "Testrestaurant T" })));
  const T = r.json.restaurant?.id;
  ok("aanmaken: 201 en restaurant bestaat (aan)", r.status === 201 && (await one("select is_active from restaurants where id=$1 and name='Testrestaurant T'", [T])).is_active === true, JSON.stringify(r));
  let l = await laatste();
  ok("aanmaken: gelogd (actie, restaurant, beheerder)", l.action === "restaurant_aangemaakt" && l.restaurant_id === T && l.admin_user_id === ORPH, JSON.stringify(l));

  // aan/uit
  r = await res(await restaurantRoute.PATCH(req("PATCH", { isActive: false }), { params: { id: RA } }));
  ok("A uitzetten: 200, database uit, gelogd", r.status === 200 && (await isA()) === false && (await laatste()).action === "restaurant_uit", JSON.stringify(r));
  as("owner"); let e: any = null; try { await requireRole("MANAGE_INVOICES"); } catch (x) { e = x; }
  ok("A uit: owner A wordt geweigerd (fase 2 werkt via het scherm)", e instanceof PermissionError && e.status === 403 && /restaurant staat uit/i.test(e.message), String(e));
  as("admin");
  r = await res(await restaurantRoute.PATCH(req("PATCH", { isActive: true }), { params: { id: RA } }));
  ok("A weer aanzetten: 200, database aan, gelogd", r.status === 200 && (await isA()) === true && (await laatste()).action === "restaurant_aan", JSON.stringify(r));
  s0 = await stand();
  r = await res(await restaurantRoute.PATCH(req("PATCH", { isActive: false }), { params: { id: ONBEKEND } }));
  ok("onbekend restaurant: 404 en niets gewijzigd (ook geen logregel)", r.status === 404 && (await stand()) === s0, JSON.stringify(r));
  r = await res(await restaurantRoute.PATCH(req("PATCH", { isActive: "nee" }), { params: { id: RA } }));
  ok("ongeldige status: 400 en niets gewijzigd", r.status === 400 && (await stand()) === s0, JSON.stringify(r));
  r = await res(await restaurantRoute.PATCH(req("PATCH", { isActive: false }), { params: { id: "geen-uuid" } }));
  ok("ongeldig id: 400 en niets gewijzigd", r.status === 400 && (await stand()) === s0, JSON.stringify(r));

  // eigenaar uitnodigen
  r = await res(await ownerRoute.POST(req("POST", { email: "t.owner@staging.test", fullName: "Eigenaar T" }), { params: { id: T } }));
  const p = await one("select u.restaurant_id, u.role, u.is_active from users u join auth.users a on a.id=u.id where a.email='t.owner@staging.test'");
  ok("eigenaar uitnodigen: 201, profiel owner in restaurant T", r.status === 201 && p.restaurant_id === T && p.role === "owner" && p.is_active === true, JSON.stringify(r) + JSON.stringify(p));
  l = await laatste();
  ok("eigenaar uitnodigen: gelogd met e-mail", l.action === "eigenaar_uitgenodigd" && l.restaurant_id === T && l.details?.email === "t.owner@staging.test", JSON.stringify(l));
  U.ownerT = { id: await uid("t.owner@staging.test") }; as("ownerT");
  let ctx: any = null; try { ctx = await requireRole("MANAGE_TEAM"); } catch (x) { ctx = x; }
  ok("nieuwe eigenaar T: toegang tot eigen restaurant", ctx?.restaurantId === T && ctx?.role === "owner", String(ctx?.message ?? JSON.stringify(ctx)));
  as("admin"); s0 = await stand();
  r = await res(await ownerRoute.POST(req("POST", { email: "a.owner@staging.test", fullName: "Kaper" }), { params: { id: T } }));
  ok("bestaand e-mailadres: 400 'al in gebruik', niets gewijzigd (owner A blijft in A)", r.status === 400 && /al in gebruik/i.test(r.json.error ?? "") && (await stand()) === s0
     && (await one("select restaurant_id from users where id=$1", [U.owner.id])).restaurant_id === RA, JSON.stringify(r));
  r = await res(await ownerRoute.POST(req("POST", { email: "nieuw@staging.test", fullName: "X" }), { params: { id: ONBEKEND } }));
  ok("eigenaar voor onbekend restaurant: 404, geen account aangemaakt", r.status === 404 && (await stand()) === s0, JSON.stringify(r));

  // logboek
  r = await res(await logRoute.GET());
  ok("logboek: 200, nieuwste eerst, met e-mail van de beheerder", r.status === 200 && r.json.log?.[0]?.action === "eigenaar_uitgenodigd" && r.json.log?.[0]?.adminEmail === "orphan@staging.test"
     && r.json.log?.[0]?.restaurantName === "Testrestaurant T", JSON.stringify(r).slice(0, 300));

  // ===== 3. fouten zichtbaar en fail closed
  // logregel kan niet worden opgeslagen (database weigert) -> de actie zelf mislukt ook (één transactie, migratie 0027)
  await q.query("alter table platform_log add constraint proef_log_faalt check (false) not valid");
  s0 = await stand();
  r = await res(await restaurantRoute.PATCH(req("PATCH", { isActive: false }), { params: { id: T } }));
  ok("logregel faalt: uitzetten 500 met zichtbare melding, restaurant blijft aan", r.status === 500 && /proef_log_faalt/.test(r.json.error ?? "") && (await stand()) === s0, JSON.stringify(r) + ` ${s0} -> ${await stand()}`);
  r = await res(await restaurantsRoute.POST(req("POST", { name: "Mag niet bestaan" })));
  ok("logregel faalt: aanmaken 500, geen restaurant", r.status === 500 && (await stand()) === s0, JSON.stringify(r) + ` ${s0} -> ${await stand()}`);
  r = await res(await ownerRoute.POST(req("POST", { email: "t.tweede@staging.test", fullName: "Tweede" }), { params: { id: T } }));
  ok("logregel faalt: eigenaar uitnodigen mislukt, geen profiel en nieuw inlogaccount opgeruimd", r.status === 400 && /proef_log_faalt/.test(r.json.error ?? "") && (await stand()) === s0
     && !(await one("select 1 as x from auth.users where email='t.tweede@staging.test'")).x, JSON.stringify(r) + ` ${s0} -> ${await stand()}`);
  await q.query("alter table platform_log drop constraint proef_log_faalt");
  cfg.rpcFault = "is_platform_admin";
  r = await res(await restaurantsRoute.GET());
  ok("fout bij is_platform_admin: 403 (fail closed)", r.status === 403, JSON.stringify(r));
  cfg.rpcFault = undefined;
  await q.query("update platform_admins set is_active = false where user_id=$1", [ORPH]);
  s0 = await stand(); const rr = await alle();
  ok("uitgezette beheerder: alle 5 routes 403, niets gewijzigd", rr.every((x) => x.status === 403) && (await stand()) === s0, JSON.stringify(rr.map((x) => x.status)));
  await q.query("update platform_admins set is_active = true where user_id=$1", [ORPH]);
  r = await res(await companiesRoute.GET());
  ok("beheerder heeft geen toegang tot restaurantroutes (geen profiel)", r.status === 401 || r.status === 403, JSON.stringify(r));
  let pe: any = null; try { await requirePlatformAdmin(); } catch (x) { pe = x; }
  ok("na herstel: beheerder weer toegelaten", pe === null, String(pe));

  // ===== 4. teambeheer gebruikt dezelfde uitnodigingsstap (inviteProfile): gedrag ongewijzigd
  as("owner"); const logA = (await one("select count(*)::int n from activity_log where restaurant_id=$1", [RA])).n;
  r = await res(await teamRoute.POST(req("POST", { email: "a.nieuw@staging.test", fullName: "Nieuwe Medewerker", role: "bediening" })));
  const nm = await one("select u.restaurant_id, u.role from users u join auth.users a on a.id=u.id where a.email='a.nieuw@staging.test'");
  ok("team: owner A nodigt medewerker uit -> 201, profiel in A, activiteit gelogd", r.status === 201 && nm.restaurant_id === RA && nm.role === "bediening"
     && (await one("select count(*)::int n from activity_log where restaurant_id=$1", [RA])).n === logA + 1, JSON.stringify(r) + JSON.stringify(nm));
  s0 = await stand();
  r = await res(await teamRoute.POST(req("POST", { email: "b.owner@staging.test", fullName: "Kaper", role: "owner" })));
  ok("team: e-mailadres uit restaurant B -> fout 'al in gebruik', niets gewijzigd", r.status === 500 && /al in gebruik/i.test(r.json.error ?? "") && (await stand()) === s0, JSON.stringify(r));

  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
