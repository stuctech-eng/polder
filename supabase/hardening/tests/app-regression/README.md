# App-regressietests (lokaal, tegen een echte Postgres)

Bewaard uit de 7b-sessie (9 okt 2026) zodat ze niet verloren gaan. Ze draaien de ECHTE routes uit de repo met een nep-supabase-client (`fake-supabase.js`) die SQL uitvoert op een lokale Postgres met de migraties 0001–0022 (+ eventueel 0023).

- `t7.ts`  — volledige regressie (bonnen, goedkeuring, facturatie, 7b-scenario's, opnieuw indienen): 173 checks. Verwacht de database MET 0023 (de "database: closed -> invoiced geweigerd"-checks). Zonder 0023 (productiestand): 159 PASS + 14 FAIL, alle 14 in de 7b-keten (5 directe databasecontroles + 9 vervolgstappen; gemeten 10 okt, eerder als 13 genoemd).
- `t8.ts`  — voorcontrole app-release ZONDER 0023 (database op 0022): 39 checks (geblokkeerde bon = 400 en nul schrijfacties; falende approvals-query = fail closed; bestaande flow intact).
- `t9.ts` — fase 2 (restaurant aan/uit, database MET 0025): 23 checks. Bouwen met `build9.js`.
- `t10.ts` — platformbeheer (database MET 0026 + 0027): 31 checks (routes weigeren niet-beheerders, aanmaken, aan/uit, eigenaar uitnodigen, logboek, logregel faalt = actie faalt, fail closed, teambeheer ongewijzigd). Bouwen met `build10.js`; gebruikt een schone kopie van de database (de test wijzigt data).
- `fake-supabase.js` — nep-client; `cfg.fault = { table, mode: "error" | "throw" }` injecteert fouten op SELECTs van een tabel; `cfg.writeFault = "<tabel>"` op schrijfacties; `cfg.rpcFault = "<functie>"` op rpc; rpc met argumenten (`rpc(fn, { p_a: … })`). Met de service-sleutel ook `auth.admin` (getUserById, inviteUserByEmail, deleteUser) rechtstreeks op `auth.users`.
- `build.js` / `build8.js` — bundelen `t7.ts` / `t8.ts` met esbuild; aanroep: `node build.js <projectmap met node_modules>`.
- Gebruik: `SCEN_FILE=supabase/hardening/tests/invoice-block-scenarios.json NODE_PATH=<node_modules met pg> node t7.js`.

LET OP (10 okt: ook gedraaid vóór/na migratie 0024, per regel identiek): de paden in de scripts zijn die van de sandbox (`/home/pgtest`, poort 55432, database `s3`) en moeten voor een andere omgeving worden aangepast. De database wordt opgebouwd met `supabase/hardening/tests/local-build.sh` (+ migraties 0020–0022, eventueel 0023).
