// Mail-links (wachtwoord herstellen, uitnodiging): de server controleert de link via /auth/confirm (token_hash + verifyOtp).
// Geen database nodig. Bouwen: node build11.js <repo>; draaien: NODE_PATH=<node_modules met pg> node t11.js
import { NextRequest } from "next/server";
import { GET } from "@/app/auth/confirm/route";
import { parseEmailLinkType, safeNextPath, parseHashSession } from "@/lib/auth/email-link";
import { POST as forgotPOST } from "@/app/api/auth/forgot-password/route";
// @ts-ignore
import { cfg } from "@supabase/supabase-js";
let pass = 0, fail = 0; const out: string[] = [];
function ok(name: string, c: boolean, d = "") { (c ? pass++ : fail++); out.push(`${c ? "PASS" : "FAIL"} ${name}${c ? "" : "  -> " + d}`); }
(globalThis as any).__cur = { id: "" };
const go = async (qs: string) => {
  cfg.verifyCalls = [];
  const r = await GET(new NextRequest("https://polder.vercel.app/auth/confirm" + qs));
  const loc = new URL(r.headers.get("location") ?? "http://leeg/");
  return { status: r.status, path: loc.pathname, host: loc.host, link: loc.searchParams.get("link"), detail: loc.searchParams.get("detail"), calls: cfg.verifyCalls as any[] };
};
(async () => {
  // pure helpers
  ok("type: alleen recovery en invite", parseEmailLinkType("recovery") === "recovery" && parseEmailLinkType("invite") === "invite"
     && parseEmailLinkType("signup") === null && parseEmailLinkType(null) === null);
  ok("next: eigen pad toegestaan", safeNextPath("/platform") === "/platform");
  ok("next: andere site geweigerd (//, https:, /\\, leeg)", ["//evil.com", "https://evil.com", "/\\evil.com", "", null].every((n) => safeNextPath(n as any) === "/reset-password"));

  let r = await go("?token_hash=geldig-recovery&type=recovery");
  ok("geldige herstel-link: door naar /reset-password, server controleert met verifyOtp(recovery)", r.status === 307 && r.path === "/reset-password" && !r.link
     && r.calls.length === 1 && r.calls[0].type === "recovery" && r.calls[0].token_hash === "geldig-recovery", JSON.stringify(r));
  r = await go("?token_hash=geldig-invite&type=invite");
  ok("geldige uitnodiging: door naar /reset-password", r.path === "/reset-password" && !r.link && r.calls[0]?.type === "invite", JSON.stringify(r));
  r = await go("?token_hash=oud-of-gebruikt&type=recovery");
  ok("verlopen/gebruikte link: /reset-password met reden 'ongeldig' en de technische melding", r.path === "/reset-password" && r.link === "ongeldig" && /expired/.test(r.detail ?? ""), JSON.stringify(r));
  r = await go("?token_hash=geldig-invite&type=recovery");
  ok("link van ander type: ongeldig", r.link === "ongeldig", JSON.stringify(r));
  r = await go("?type=recovery");
  ok("zonder token: reden 'ontbreekt', geen controle uitgevoerd", r.link === "ontbreekt" && r.calls.length === 0, JSON.stringify(r));
  r = await go("?token_hash=geldig-signup&type=signup");
  ok("onbekend type: reden 'ontbreekt', geen controle uitgevoerd", r.link === "ontbreekt" && r.calls.length === 0, JSON.stringify(r));
  r = await go("?token_hash=geldig-recovery&type=recovery&next=/platform");
  ok("next=/platform: daarheen", r.path === "/platform" && r.host === "polder.vercel.app", JSON.stringify(r));
  r = await go("?token_hash=geldig-recovery&type=recovery&next=//evil.com/x");
  ok("next=//evil.com: blijft op eigen site (/reset-password)", r.host === "polder.vercel.app" && r.path === "/reset-password", JSON.stringify(r));
  r = await go("?token_hash=geldig-recovery&type=recovery&next=https://evil.com");
  ok("next=https://evil.com: blijft op eigen site", r.host === "polder.vercel.app" && r.path === "/reset-password", JSON.stringify(r));

  // ===== herstelmail via de server (implicit flow): werkt zonder aangepast Supabase-sjabloon
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "anon"; delete process.env.NEXT_PUBLIC_SITE_URL;
  const forgot = async (body: any) => { cfg.resets = []; const r = await forgotPOST(new Request("https://polder.vercel.app/api/auth/forgot-password",
    { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) })); return { status: r.status, json: await r.json(), resets: cfg.resets as any[] }; };
  let f = await forgot({ email: "stuctech@gmail.com" });
  ok("herstel aanvragen: 200, server vraagt aan met implicit flow, anon-sleutel en link naar /reset-password",
     f.status === 200 && f.resets.length === 1 && f.resets[0].flowType === "implicit" && f.resets[0].key === "anon"
     && f.resets[0].redirectTo === "https://polder.vercel.app/reset-password" && f.resets[0].email === "stuctech@gmail.com", JSON.stringify(f));
  f = await forgot({ email: "geen-adres" });
  ok("ongeldig e-mailadres: 400, niets aangevraagd", f.status === 400 && f.resets.length === 0, JSON.stringify(f));
  cfg.resetFault = "For security purposes, you can only request this after 42 seconds";
  f = await forgot({ email: "stuctech@gmail.com" });
  ok("fout van Supabase (wachttijd): 500 met zichtbare melding", f.status === 500 && /42 seconds/.test(f.json.error ?? ""), JSON.stringify(f));
  cfg.resetFault = undefined;
  // ===== #-deel van de link uitlezen (herstel en uitnodiging)
  const h1 = parseHashSession("#access_token=AT&refresh_token=RT&type=recovery") as any;
  ok("link met tokens: sessie gevonden", h1?.accessToken === "AT" && h1?.refreshToken === "RT", JSON.stringify(h1));
  const h2 = parseHashSession("#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired") as any;
  ok("verlopen link: foutmelding uit de link", /invalid or has expired/.test(h2?.error ?? ""), JSON.stringify(h2));
  ok("geen of half #-deel: niets", parseHashSession("") === null && parseHashSession("#access_token=AT") === null);

  console.log(out.join("\n")); console.log(`${pass} PASS, ${fail} FAIL`); process.exit(fail ? 1 : 0);
})().catch((err) => { console.log(out.join("\n")); console.log("FOUT", err); process.exit(2); });
