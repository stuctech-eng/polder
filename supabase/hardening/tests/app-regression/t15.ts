// Hardening stap 11 (migraties 0033-0034): app-test tegen een lokale database MET 0034. Echte schrijfroutes voor bedrijven,
// onderdelen, verplichte velden en dagafsluiting; de nep-client voert SQL uit als de ingelogde gebruiker (RLS is echt).
// Bouwen: node build15.js <repo>; draaien: PGHOST=… PGPORT=… PGUSER=… TESTDB=… NODE_PATH=… node t15.js
import * as companies from "@/app/api/companies/route";
import * as company from "@/app/api/companies/[id]/route";
import * as departments from "@/app/api/companies/[id]/departments/route";
import * as costCenters from "@/app/api/companies/[id]/cost-centers/route";
import * as projects from "@/app/api/companies/[id]/projects/route";
import * as codes from "@/app/api/companies/[id]/codes/route";
import * as requiredFields from "@/app/api/companies/[id]/required-fields/route";
import * as dailyClosing from "@/app/api/daily-closing/route";
import { createSupabaseServerClient } from "@/lib/supabase/server";
// @ts-ignore
import { end } from "@supabase/supabase-js";
import { Client } from "pg";
process.env.SUPABASE_SERVICE_ROLE_KEY = "service"; process.env.NEXT_PUBLIC_SUPABASE_URL = "x"; process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "anon";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const RA = "a0000000-0000-0000-0000-000000000001";
const A = (n: number) => `a0000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
(async () => {
  const q = new Client({ host: process.env.PGHOST, port: +(process.env.PGPORT || 55432), database: process.env.TESTDB, user: process.env.PGUSER });
  await q.connect();
  const one = async (sql: string, p: any[] = []) => (await q.query(sql, p)).rows[0] ?? {};
  const uid = async (e: string) => (await one("select id from auth.users where email=$1", [e])).id;
  const U: any = { admin: { id: await uid("a.admin@staging.test") }, mgr: { id: await uid("a.manager@staging.test") },
                   bed: { id: await uid("a.bediening@staging.test") }, owner: { id: await uid("a.owner@staging.test") } };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const req = (method: string, body?: any) => new Request("http://x/", { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const res = async (r: Response) => ({ status: r.status, json: await r.json().catch(() => ({})) });
  const C = A(100);

  // ===== 1. administratie (MANAGE_COMPANIES + MANAGE_SETTINGS): alle schrijfroutes werken
  as("admin");
  let r = await res(await companies.POST(req("POST", { name: "Stap 11 BV" })));
  ok("1 bedrijf aanmaken: 201", r.status === 201 && !!r.json.company?.id, JSON.stringify(r));
  const nieuw = r.json.company?.id;
  r = await res(await company.PATCH(req("PATCH", { name: "Stap 11 BV gewijzigd" }), { params: { id: nieuw } }));
  ok("2 bedrijf wijzigen: 200 en naam in de database", r.status === 200 && (await one("select name from companies where id=$1", [nieuw])).name === "Stap 11 BV gewijzigd", JSON.stringify(r));
  r = await res(await departments.POST(req("POST", { name: "Afd 11" }), { params: { id: C } }));
  ok("3 afdeling aanmaken: 201", r.status === 201, JSON.stringify(r));
  r = await res(await costCenters.POST(req("POST", { name: "KP 11" }), { params: { id: C } }));
  ok("4 kostenplaats aanmaken: 201", r.status === 201, JSON.stringify(r));
  r = await res(await projects.POST(req("POST", { name: "Project 11" }), { params: { id: C } }));
  ok("5 project aanmaken: 201", r.status === 201, JSON.stringify(r));
  r = await res(await codes.POST(req("POST", { type: "po", code: "PO-11" }), { params: { id: C } }));
  ok("6 bedrijfscode aanmaken: 201", r.status === 201, JSON.stringify(r));
  r = await res(await requiredFields.PUT(req("PUT", { receiptFields: { department: true } }), { params: { id: C } }));
  ok("7 verplichte velden opslaan (configurations): 200", r.status === 200, JSON.stringify(r));
  r = await res(await requiredFields.PUT(req("PUT", { receiptFields: { department: false } }), { params: { id: C } }));
  ok("8 verplichte velden nogmaals opslaan (update): 200", r.status === 200, JSON.stringify(r));

  // ===== 2. dagafsluiting: manager op eigen naam
  as("mgr");
  r = await res(await dailyClosing.POST(req("POST", { date: "2001-03-01" })));
  ok("9 manager sluit de dag af: 201 en closed_by = manager", r.status === 201 && r.json.closing?.closed_by === U.mgr.id, JSON.stringify(r));
  r = await res(await companies.POST(req("POST", { name: "Manager BV" })));
  ok("10 manager maakt bedrijf aan: 403 van de route", r.status === 403, JSON.stringify(r));

  // ===== 3. rechtstreeks via de database
  let c = createSupabaseServerClient();
  let d = await c.from("daily_closings").insert({ restaurant_id: RA, closing_date: "2001-03-02", closed_by: U.owner.id }).select("id");
  ok("11 manager zet afsluiting op naam van de owner: geweigerd (RLS)", !!d.error && /row-level security/.test(d.error.message), JSON.stringify(d));
  let u = await c.from("daily_closings").update({ total_revenue: 1 }).eq("closing_date", "2001-03-01").select("id");
  ok("12 manager wijzigt eigen afsluiting: 0 rijen", !u.error && (u.data ?? []).length === 0, JSON.stringify(u));
  as("bed"); c = createSupabaseServerClient();
  let s = await c.from("companies").select("id").eq("restaurant_id", RA);
  let s2 = await c.from("departments").select("id").eq("company_id", C);
  ok("13 bediening leest bedrijven en afdelingen (rekening openen)", !s.error && (s.data ?? []).length > 0 && (s2.data ?? []).length > 0, JSON.stringify([s, s2]).slice(0, 200));
  let dc = await c.from("daily_closings").select("id");
  ok("14 bediening leest geen dagafsluitingen", !dc.error && (dc.data ?? []).length === 0, JSON.stringify(dc));
  u = await c.from("companies").update({ name: "x" }).eq("id", C).select("id");
  ok("15 bediening wijzigt bedrijf: 0 rijen", !u.error && (u.data ?? []).length === 0, JSON.stringify(u));
  as("owner"); c = createSupabaseServerClient();
  let w = await c.from("workflow_rules").delete().eq("company_id", C).select("id");
  let ip = await c.from("integration_plugins").select("id");
  ok("16 owner wist workflowregel: 0 rijen; owner leest integration_plugins: 0 rijen", !w.error && (w.data ?? []).length === 0 && !ip.error && (ip.data ?? []).length === 0, JSON.stringify([w, ip]));

  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
