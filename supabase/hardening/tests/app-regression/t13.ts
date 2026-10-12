// Facturatieregel (12 okt 2026): het ongebruikte vakje "Goedkeuring vereist voor factureren" is weg.
// De route slaat requires_approval niet meer op (ook niet als een oude client het meestuurt) en de bestaande waarde blijft
// ongewijzigd. GET heeft nu ook een rolcontrole. Bouwen: node build13.js <repo>; draaien met PGHOST/PGPORT/PGUSER/TESTDB.
import * as rule from "@/app/api/companies/[id]/workflow-rule/route";
import { Client } from "pg";
// @ts-ignore
import { end } from "@supabase/supabase-js";
process.env.SUPABASE_SERVICE_ROLE_KEY = "service"; process.env.NEXT_PUBLIC_SUPABASE_URL = "x";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
const C = "a0000000-0000-0000-0000-000000000100";
(async () => {
  const q = new Client({ host: process.env.PGHOST, port: +(process.env.PGPORT || 55432), database: process.env.TESTDB, user: process.env.PGUSER });
  await q.connect();
  const uid = async (e: string) => (await q.query("select id from auth.users where email=$1", [e])).rows[0].id;
  const U: any = { owner: { id: await uid("a.owner@staging.test") }, bed: { id: await uid("a.bediening@staging.test") } };
  const as = (k: string) => { (globalThis as any).__cur = U[k]; };
  const req = (body: any) => new Request("http://x/", { method: "PUT", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  const rij = async () => (await q.query("select invoice_frequency f, requires_approval a from workflow_rules where company_id=$1", [C])).rows[0] ?? {};
  // bestaande rij met requires_approval = true (oude waarde) moet ongewijzigd blijven
  await q.query("set session_replication_role = replica");
  await q.query("delete from workflow_rules where company_id=$1", [C]);
  await q.query("insert into workflow_rules (restaurant_id, company_id, invoice_frequency, requires_approval) values ('a0000000-0000-0000-0000-000000000001',$1,'immediate',true)", [C]);
  await q.query("set session_replication_role = origin");
  as("owner");
  let r = await rule.PUT(req({ invoiceFrequency: "weekly" }), { params: { id: C } });
  let x = await rij();
  ok("opslaan zonder het vakje: 200, frequentie gewijzigd, oude waarde requires_approval ongewijzigd (true)", r.status === 200 && x.f === "weekly" && x.a === true, `${r.status} ${JSON.stringify(x)}`);
  r = await rule.PUT(req({ invoiceFrequency: "monthly", requiresApproval: false }), { params: { id: C } });
  x = await rij();
  ok("oude client stuurt requiresApproval mee: geaccepteerd maar genegeerd (blijft true)", r.status === 200 && x.f === "monthly" && x.a === true, `${r.status} ${JSON.stringify(x)}`);
  await q.query("delete from workflow_rules where company_id=$1", [C]);
  r = await rule.PUT(req({ invoiceFrequency: "immediate" }), { params: { id: C } });
  x = await rij();
  ok("nieuwe regel: aangemaakt met de standaardwaarde (false)", r.status === 200 && x.f === "immediate" && x.a === false, `${r.status} ${JSON.stringify(x)}`);
  r = await rule.GET(new Request("http://x/"), { params: { id: C } });
  ok("GET als owner: 200", r.status === 200, String(r.status));
  as("bed"); r = await rule.GET(new Request("http://x/"), { params: { id: C } });
  ok("GET als bediening (geen MANAGE_SETTINGS): 403", r.status === 403, String(r.status));
  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
