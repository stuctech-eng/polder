// Bon toevoegen: leesbare Nederlandse melding in plaats van "Validatiefout" (16 okt 2026). Echte route; database met 0042.
// Bouwen: node build20.js <repo>; draaien: PGHOST=… PGPORT=… PGUSER=… TESTDB=… NODE_PATH=… node t20.js
import * as tabReceipts from "@/app/api/open-tabs/[id]/receipts/route";
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
  (globalThis as any).__cur = { id: (await one("select id from auth.users where email='a.owner@staging.test'")).id };
  const TAB = A(9950);
  await q.query("insert into open_tabs (id, restaurant_id, company_id, status) values ($1,$2,null,'open')", [TAB, RA]);
  const aantal = async () => (await one("select (select count(*)::int from receipts where open_tab_id=$1) b, (select count(*)::int from receipt_lines) l", [TAB])) as any;
  const post = async (body: any) => { const r = await tabReceipts.POST(new Request("http://x/", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }), { params: { id: TAB } }); return { status: r.status, json: await r.json().catch(() => ({})) }; };
  const regel = (x: any = {}) => ({ description: "Koffie", quantity: 1, unitPrice: 3, vatRate: 9, ...x });
  const gevallen: [string, any, string][] = [
    ["alleen een bonnummer (lege omschrijving, zoals het scherm hem stuurt)", { receiptNumber: "1", lines: [regel({ description: "" })] }, "Productregel 1: vul een omschrijving in."],
    ["omschrijving met alleen spaties", { lines: [regel({ description: "   " })] }, "Productregel 1: vul een omschrijving in."],
    ["tweede regel aantal 0", { lines: [regel(), regel({ quantity: 0 })] }, "Productregel 2: het aantal moet groter zijn dan 0."],
    ["negatieve prijs", { lines: [regel({ unitPrice: -1 })] }, "Productregel 1: de prijs mag niet negatief zijn."],
    ["prijs is geen getal", { lines: [regel({ unitPrice: "abc" })] }, "Productregel 1: de prijs is geen getal."],
    ["geen regels", { lines: [] }, "Voeg minstens één productregel toe."],
  ];
  for (const [nm, body, verwacht] of gevallen) {
    const voor = JSON.stringify(await aantal()); const r = await post(body);
    ok(`${nm}: 400 met "${verwacht}", niets opgeslagen`, r.status === 400 && r.json.error === verwacht && JSON.stringify(await aantal()) === voor, JSON.stringify(r.json.error));
  }
  const r = await post({ receiptNumber: "OK-1", lines: [regel({ description: "  Thee  " })] });
  ok("geldige bon: 201, omschrijving zonder spaties eromheen opgeslagen", r.status === 201 && (await one("select description from receipt_lines where receipt_id=$1", [r.json.receipt?.id])).description === "Thee", JSON.stringify(r.json).slice(0, 200));
  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`);
  await q.end(); await end(); process.exit(fail ? 1 : 0);
})().catch(async (err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
