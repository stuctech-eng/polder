// Hardening stap 10 (migraties 0031-0032, rolrechten facturen + factuurwacht): app-test tegen een lokale database MET 0032.
// Echte routes; alleen de Supabase-clients, react.cache en de mailer zijn gestubd. De nep-client voert SQL uit als de ingelogde
// gebruiker (RLS en triggers zijn echt). Bouwen: node build14.js <repo>; draaien: PGHOST=… PGPORT=… PGUSER=… TESTDB=… NODE_PATH=… node t14.js
import * as payments from "@/app/api/invoices/[id]/payments/route";
import * as invoiceRoute from "@/app/api/invoices/[id]/route";
import { createSupabaseServerClient } from "@/lib/supabase/server";
// @ts-ignore
import { cfg, end } from "@supabase/supabase-js";
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
                   bed: { id: await uid("a.bediening@staging.test") } };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const req = (method: string, body?: any) => new Request("http://x/", { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const res = async (r: Response) => ({ status: r.status, json: await r.json().catch(() => ({})) });
  const status = async (id: string) => (await one("select status from invoices where id=$1", [id])).status;
  const npay = async (id: string) => (await one("select count(*)::int n from payments where invoice_id=$1", [id])).n;
  const draft = async (n: number, total: number) => {
    await q.query("insert into invoices (id, restaurant_id, company_id, invoice_number, status, total) values ($1,$2,$3,$4,'draft',$5)", [A(n), RA, A(100), "T-" + n, total]);
    return A(n);
  };
  const pay = async (id: string, amount: number) => res(await payments.POST(req("POST", { amount, method: "pin" }), { params: { id } }));
  const patch = async (id: string, s: string) => res(await invoiceRoute.PATCH(req("PATCH", { status: s }), { params: { id } }));

  // ===== 1. de betalingsflow werkt met de nieuwe database (administratie heeft MANAGE_INVOICES)
  as("admin");
  let r = await pay(A(500), 5);
  ok("1 deelbetaling op draft-factuur: 201, factuur draft -> sent", r.status === 201 && (await status(A(500))) === "sent", JSON.stringify(r));
  let f = await draft(9201, 10);
  r = await pay(f, 10);
  ok("2 volledige betaling op draft-factuur (besluit D6): 201, factuur draft -> paid", r.status === 201 && r.json.isFullyPaid === true && (await status(f)) === "paid", JSON.stringify(r));
  r = await pay(A(501), 21.8);
  ok("3 restbedrag op verzonden factuur: 201, sent -> paid", r.status === 201 && (await status(A(501))) === "paid", JSON.stringify(r));
  let n0 = await npay(A(502)); r = await pay(A(502), 1);
  ok("4 betaling op betaalde factuur: 400 van de app, geen betaling erbij", r.status === 400 && (await npay(A(502))) === n0, JSON.stringify(r));

  // ===== 2. weigert de database de statuswijziging, dan nooit "gelukt" melden
  f = await draft(9202, 10); cfg.writeFault = "invoices";
  r = await pay(f, 10); cfg.writeFault = undefined;
  ok("5 statuswijziging mislukt: 500 met zichtbare melding, niet 201", r.status === 500 && /factuurstatus kon niet/.test(r.json.error ?? ""), JSON.stringify(r));
  ok("6 en de melding zegt eerlijk dat de betaling er wel staat (1 betaling, factuur nog draft)", (await npay(f)) === 1 && (await status(f)) === "draft" && /Betaling is geregistreerd/.test(r.json.error ?? ""), JSON.stringify(r));

  // ===== 3. de echte database weigert een verboden overgang; de app toont de melding
  f = await draft(9203, 10);
  r = await patch(f, "overdue");
  ok("7 draft -> overdue via de route: database weigert, melding zichtbaar, status ongewijzigd", r.status === 500 && /Ongeldige factuurstatus/.test(r.json.error ?? "") && (await status(f)) === "draft", JSON.stringify(r));
  f = await draft(9204, 10); await patch(f, "sent");
  r = await patch(f, "overdue");
  ok("8 sent -> overdue via de route: 200", r.status === 200 && (await status(f)) === "overdue", JSON.stringify(r));

  // ===== 4. rollen: de routes en de database zeggen hetzelfde
  as("mgr"); r = await pay(A(9204), 1);
  ok("9 manager registreert betaling: 403 van de route", r.status === 403, JSON.stringify(r));
  let c = createSupabaseServerClient();
  let s = await c.from("invoices").select("id, payments(amount)").eq("restaurant_id", RA);
  ok("10 manager (dashboard, VIEW_REVENUE) leest facturen met betalingen", !s.error && (s.data ?? []).length > 0 && (s.data ?? []).some((x: any) => (x.payments ?? []).length > 0), JSON.stringify(s).slice(0, 300));
  let u = await c.from("invoices").update({ status: "paid" }).eq("id", A(9204)).select("id");
  ok("11 manager rechtstreeks via de database: factuur op paid zetten raakt 0 rijen", !u.error && (u.data ?? []).length === 0 && (await status(A(9204))) === "overdue", JSON.stringify(u));
  as("bed"); c = createSupabaseServerClient();
  s = await c.from("invoices").select("id").eq("restaurant_id", RA);
  let p = await c.from("payments").select("id");
  ok("12 bediening leest geen facturen en geen betalingen meer (0 rijen, geen fout)", !s.error && !p.error && (s.data ?? []).length === 0 && (p.data ?? []).length === 0, JSON.stringify([s, p]).slice(0, 300));
  as("admin"); c = createSupabaseServerClient();
  let d = await c.from("payments").delete().eq("invoice_id", A(502)).select("id");
  ok("13 administratie wist betaling rechtstreeks: 0 rijen, betaling blijft", !d.error && (d.data ?? []).length === 0 && (await npay(A(502))) === n0, JSON.stringify(d));

  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
