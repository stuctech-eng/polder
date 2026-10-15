# Security hardening — voorbereiding en testharnas (STAP 0)

**Status (15 okt 2026): stappen 0–7 + 0022 in productie; 0023 voorbereid, niet uitgevoerd; stap 8 (tenantswitch, 0024) in productie en akkoord (10 okt); stap 9 (restaurant aan/uit, 0025) in productie en akkoord (10 okt, app v1.0.80); platformbeheer (0026 + 0027) in productie en akkoord (11 okt, app v1.0.83); fase 4 modules (0028–0030) in productie en akkoord (12 okt, app v1.0.88); stap 10 (rolrechten facturen, 0031–0032) in productie en rooktest geslaagd (13 okt, app v1.0.91); stap 11 (0033–0034) in productie en rooktest geslaagd (13 okt, v1.0.94); stap 12 (app + 0035) in productie en rooktest geslaagd (13 okt, v1.0.96); stap 13 (0036, overbodige rechten) in productie en rooktest geslaagd (15 okt, v1.0.98).** Niets in deze map wijzigt productie zonder expliciete GO.
Plan: `docs/security-hardening-plan.md` · Audit: `docs/architecture.md` sectie 13 (en 13.7 = Stap 0-resultaat).

## Wat staat waar

| Bestand | Draai je waar | Doel |
|---|---|---|
| `prod-readonly-checks.sql` | **Productie** (Supabase SQL Editor) — alleen SELECT | Eén resultaattabel: baseline (A), datacompatibiliteit (B), D4-onderzoek (C). Bevat referentie-fingerprints in de kop. |
| `staging-seed.sql` | **Alleen staging / lokaal** — weigert te draaien als het productierestaurant bestaat | Restaurant A en B (owner, manager, administratie, bediening, keuken + 1 gedeactiveerde), leeg restaurant C, wees-account, voorbeelddata in alle statussen |
| `tests/00_harness.sql` | Alleen staging / lokaal (eist de marker van de seed) | Schema `hardening_test`: `run(stap)`, `summary(stap)`, view `known_weaknesses`. Elke test draait in een subtransactie die **altijd** wordt teruggedraaid |
| `tests/10_cases.sql` | idem | De securitytestmatrix (gegenereerd) |
| `tests/generate_cases.py` | lokaal | Bron van de testcases; hergenereert `10_cases.sql` |
| `tests/local-*.sql`, `tests/local-build.sh` | Alleen lokale Postgres | Nabootsing van auth/storage/standaardrechten + bouwscript |
| `permission-baseline.json` | — | Exacte kopie van de TypeScript-rechtenmatrix (11 rechten × 5 rollen = 55 rijen) |
| `prod-tenantswitch-checks.sql` | **Productie** — alleen lezen, eindigt met rollback | Stand van de 15 tenant-policies: vóór 0024 15 × "oud", na 0024 15 × "nieuw" |
| `tests/tenantswitch-tests.sh` | Alleen lokaal (maakt eigen kopie-databases) | Migratie- en rollbacktests voor 0024 (22 checks) |
| `tests/aanuit-tests.sh` | Alleen lokaal (maakt eigen kopie-databases) | Migratie- en rollbacktests voor 0025 (19 checks) |
| `prod-aanuit-checks.sql` | **Productie** — alleen lezen, eindigt met rollback | Stand van 0025: functies, kolom, my_access, dekking (lokaal staat email_settings erbij; bestaat niet in productie) |
| `tests/platform-tests.sh` | Alleen lokaal (maakt eigen kopie-databases) | Migratie- en rollbacktests voor 0026 en 0027 (22 checks) |
| `prod-platform-checks.sql` | **Productie** — alleen lezen, eindigt met rollback | Stand van 0026/0027: tabellen, functie, RLS, rechten, actiefuncties, aantal beheerders |
| `tests/modules-tests.sh` | Alleen lokaal (maakt eigen kopie-databases) | Migratie- en rollbacktests voor 0028–0030 (24 checks, incl. G1 guards ongewijzigd) |
| `prod-modules-checks.sql` | **Productie** — alleen lezen, eindigt met rollback | Stand van 0028–0030, rechten, alles standaard aan, `guards_md5` (vóór en na gelijk) |
| `tests/facturen-tests.sh` | Alleen lokaal (maakt eigen kopie-databases) | Migratie-, rollback- en mutatietests voor 0031–0032 (36 checks: heen/terug exact, verkeerde volgorde afgebroken, 15 kapotte versies gevangen, twee lagen) |
| `prod-facturen-checks.sql` | **Productie** — alleen lezen, eindigt met rollback | Stand 0030/0031/0032, aantallen policies en wachttriggers, rechten, `guards_md5` (= 287f55d5…), `module_wacht_md5` en `modules_md5` vóór en na gelijk |
| `tests/pin-tests.sh` | Alleen lokaal (maakt eigen kopie-databases) | Migratie-, rollback- en mutatietests voor 0035 (27 checks; toont de exacte rechten vóór, na en na rollback: heen/terug exact, afwijkende uitgangsstand afgebroken, 6 kapotte versies gevangen, rechten op andere tabellen ongewijzigd) |
| `prod-pin-checks.sql` | **Productie** — alleen lezen, eindigt met rollback | Stand 0034/0035, kolommen, PIN leesbaar ja/nee, open kolommen, anon, server, schrijven; vijf md5's vóór en na gelijk |
| `tests/stamdata-tests.sh` | Alleen lokaal (maakt eigen kopie-databases) | Migratie-, rollback- en mutatietests voor 0033–0034 (43 checks; 42 op een basis zonder email_settings, zoals productie; o.a. rollback 0034 breekt af bij elke afwijkende policyverdeling: heen/terug exact, verkeerde volgorde afgebroken, extra policy → afgebroken, 11 kapotte versies gevangen, triggers/guards/modules/overige policies ongewijzigd) |
| `prod-stamdata-checks.sql` | **Productie** — alleen lezen, eindigt met rollback | Stand 0032/0033/0034, aantal bestaande tabellen (productie 12: geen email_settings), aantallen policies, ALL-policies in public, `dicht_ok`; `guards_md5`, `module_wacht_md5`, `modules_md5`, `overige_md5` vóór en na gelijk |
| `prod-rechten-inventaris.sql` | **Productie** — alleen lezen, eindigt met rollback | Stap 13a: alle rechten (ook MAINTAIN), policies, standaardrechten per rol, eigenaren, versie, volledig leesbaar ja/nee. Uitslag 14 okt: `tests/prod-inventaris-13a.txt` |
| `prod-rechten-checks.sql` | **Productie** — alleen lezen, eindigt met rollback | Stand 0036 via de vingerafdruk (tabel-, sequence-, kolom- en standaardrechten): `voor 0036\|34\|25\|t\|0` → `na 0036\|0\|0\|f\|0`, anders ONBEKEND; drie md5's vóór en na gelijk |
| `tests/local-prod17-stand.sql` | Alleen lokaal, alleen PostgreSQL 17 (via `local-build.sh PRODSTAND=1`) | Bootst de gemeten productiestand van 13a na; daarna is de inventaris regel voor regel gelijk aan productie |
| `tests/rechten-tests.sh` | Alleen lokaal (maakt eigen kopie-databases) | Tests voor 0036: PG17 (productiestand) 63 checks — uitgangsstand = productie, heen/terug exact, lint, MAINTAIN, standaardrechten, service_role/supabase_admin ongewijzigd, 8 afwijkende uitgangsstanden, 11 kapotte versies, kolomrechten van anon en service_role (vóór/na/kapot); PG16 4 checks (0036 breekt bewust af) |
| `prod-platform-beheerder.sql` | **Productie** — WIJZIGT (alleen met GO) | Voegt stuctech@gmail.com toe als platformbeheerder; weigert een account met restaurantprofiel |

## Testharnas gebruiken

```sql
-- na staging-seed.sql, 00_harness.sql en 10_cases.sql:
select * from hardening_test.summary(0);                       -- huidige stand: alles PASS (kolom skip = expliciet overgeslagen cases, zie 'vereist')
select * from hardening_test.known_weaknesses;                 -- de bekende zwaktes en in welke stap ze dichtgaan
select * from hardening_test.run(3) where result <> 'PASS';    -- verwachting ná hardening-stap 3
```

* `PASS` = gedrag komt overeen met de verwachting voor die stap · `FAIL` = afwijking · `OPEN` = open beslispunt (bv. D6, geen pass/fail) · `FOUT` = testopzet kapot.
* Vandaag (`run(0)`) hoort **alles PASS** te zijn: de testmatrix beschrijft de huidige, nog ongehardende productiestand. Zwaktes staan als "toegestaan nu → geweigerd na stap N".
* Na iedere hardening-stap: `run(<die stap>)` moet 100% PASS geven (behalve OPEN), én alle eerdere stappen blijven PASS.

## Migratie- en rollbackstructuur (alleen gepland — de bestanden bestaan nog NIET)

Elke stap = één migratie, één transactie, eigen rollback, daarna STOP voor controle en nieuwe GO.

| Stap | Inhoud | Migratie (gepland) | Rollback (gepland) | Toets |
|---|---|---|---|---|
| 0 | voorbereiding/testharnas | — | — | `run(0)` |
| 1 | H1 + H9 helpers, search_path, is_active | `0015_hardening_step1_helpers.sql` (**uitgevoerd lokaal; productie wacht op Dicks run**) | `rollbacks/0015_rollback.sql` | `run(1)` |
| 2 | H3 restaurants + H8a privileges | `0016_hardening_step2_restaurants_privileges.sql` (**lokaal getest**) | `rollbacks/0016_rollback.sql` | `run(2)` |
| 3 | H2 users + server-side team/uitnodiging | `0017_hardening_step3_users.sql` (**lokaal getest; eerst app-deploy, dan migratie**) | `rollbacks/0017_rollback.sql` (+ app-revert) | `run(3)` |
| 4 | H5a logs append-only | `0018_hardening_step4_logs_append_only.sql` (**lokaal getest; geen app-wijziging**) | `rollbacks/0018_rollback.sql` | `run(4)` |
| 5 | H7 cross-reference integriteit | `0019_hardening_step5_crossref.sql` (**lokaal getest; geen app-wijziging**) | `rollbacks/0019_rollback.sql` | `run(5)` |
| 6 | H6 storage | `0020_hardening_step6_storage.sql` (+ app: `upsert:false`; **lokaal getest; eerst app-deploy, dan migratie**) | `rollbacks/0020_rollback.sql` | `run(6)` |
| 7 | H4a open_tabs/receipts/receipt_lines/approvals | `0021_hardening_step7_tabs_receipts.sql` (**in productie, akkoord**) | `rollbacks/0021_rollback.sql` | `run(7)` |
| 7+ | aanscherping `approvals_guard` | `0022_hardening_step7_approvals_guard.sql` (**in productie, akkoord**) | `rollbacks/0022_rollback.sql` | `run(7)` |
| 7b | afgewezen bon niet factureren | `0023_hardening_plan7b_invoice_block.sql` + app-wijziging (**app live sinds v1.0.74; migratie 0023 voorbereid en lokaal getest, NIET uitgevoerd in productie**) | `rollbacks/0023_rollback.sql` | `run(99)` (cases staan sinds 10 okt op eigen stap 99; alleen zinvol op een database MET 0023) |
| 8 | **Tenantswitch (fase 1 meerdere restaurants)**: de 15 oude inline-policies via `my_restaurant_id()` | `0024_tenantswitch_inline_policies.sql` (**in productie, akkoord — 10 okt 2026**) | `rollbacks/0024_rollback.sql` | `run(8)` + `tests/tenantswitch-tests.sh` + `prod-tenantswitch-checks.sql` |
| 9 | **Restaurant aan/uit (fase 2)**: `restaurants.is_active`, `my_restaurant_id()`/`my_role()` met restaurantcontrole, `my_access()` | `0025_restaurant_aan_uit.sql` + app (**in productie sinds 10 okt; controle 0025/0025/ja/ja/0/false/leeg; app-test geslaagd**) | `rollbacks/0025_rollback.sql` (eerst app terug) | `run(9)` + `tests/aanuit-tests.sh` + app-test t9 + `prod-aanuit-checks.sql` |
| — | **Platformbeheer**: `platform_admins`, `platform_log`, `is_platform_admin()`; actiefuncties met logregel in één transactie (categorie PLATFORM, stap 0: geldt altijd vanaf 0027) | `0026_platformbeheer.sql` + `0027_platform_acties.sql` + app (**in productie sinds 10 okt; leesblok 0025/ja/ja/ja/ja/true/ja/0; app-test geslaagd**) | `rollbacks/0027_rollback.sql`, dan `0026_rollback.sql` (eerst app terug) | `run(9)` (PLATFORM 27/27) + `tests/platform-tests.sh` + app-test t10 + `prod-platform-checks.sql` |
| — | **Fase 4 modules**: register, `feature_aan`/`my_feature`, beheerfunctie, databasewacht `module_wacht` (categorie MODULES, stap 0) | `0028_modules.sql`, `0029_module_beheer.sql`, `0030_module_wacht.sql` + app (**in productie sinds 11 okt; eindstand 0027/ja/ja/ja/6/ja/true/true, guards_md5 ongewijzigd; rooktest geslaagd**) | `rollbacks/0030`, dan `0029`, dan `0028` (eerst app terug) | `run(9)` (MODULES 104/104) + `tests/modules-tests.sh` + app-test t12 + `prod-modules-checks.sql` |
| 10 | **H4b rolrechten facturen**: lezen VIEW_REVENUE (documents MANAGE_INVOICES), schrijven MANAGE_INVOICES, nooit wissen, betalingen nooit wijzigen; factuurwacht (D6: draft->sent\|paid, sent->paid\|overdue, overdue->paid; na draft alleen de status; paid eindstand), regels alleen bij draft, betaling > 0 en niet op een betaalde factuur (categorie FACTUURWACHT) | `0031_rolrechten_facturen.sql` + `0032_factuur_wacht.sql` + app (betalingsroute meldt een mislukte statuswijziging) (**in productie sinds 13 okt; eindstand 0032/11/0/3/true, drie md5's ongewijzigd; rooktest geslaagd**) | `rollbacks/0032`, dan `0031` (**noodmaatregel: zet ook het oude lek terug**) | `run(10)` + `tests/facturen-tests.sh` + app-test t14 + `prod-facturen-checks.sql` |
| 11 | **H4c + H4d rolrechten dagafsluiting, bedrijfsgegevens, instellingen**: dagafsluiting lezen VIEW_DAILY_CLOSING, aanmaken EXECUTE_DAILY_CLOSING op eigen naam (`closed_by = auth.uid()`); bedrijven en onderdelen lezen iedereen, schrijven MANAGE_COMPANIES; instellingen schrijven MANAGE_SETTINGS; contacts, integration_plugins, email_settings, notifications dicht; nergens wissen; daarna geen ALL-policy meer (categorie ROLRECHTEN11) | `0033_rolrechten_dagafsluiting_bedrijven.sql` + `0034_rolrechten_instellingen.sql`, geen app-wijziging (**in productie sinds 13 okt; eindstand 0034/12/22/0/0/true, vier md5's ongewijzigd; rooktest geslaagd**) | `rollbacks/0034`, dan `0033` (**noodmaatregel: zet ook het oude lek terug**) | `run(11)` + `tests/stamdata-tests.sh` + app-test t15 + `prod-stamdata-checks.sql` |
| 12 | **H10 PIN-geheimen**: authenticated leest pin_hash/pin_salt niet meer (kolomrechten, ook niet via WHERE of RETURNING); de app leest de PIN alleen op de server (service-sleutel, na de rolcontrole, fail closed) (categorie PIN12) | app (push A) **eerst**, daarna `0035_pin_kolommen.sql` (**in productie sinds 13 okt: app 18:56, migratie 18:59; eindstand 0035|true|false|8|false|true|true, md5's gelijk; rooktest geslaagd**) | `rollbacks/0035_rollback.sql` (**noodmaatregel: PIN weer leesbaar**) | `run(12)` + `tests/pin-tests.sh` + app-test t16 + `prod-pin-checks.sql` |
| 13 | **H8b overbodige rechten**: authenticated alleen nog rechten waar een policy bij hoort (34 ingetrokken), geen MAINTAIN voor anon/authenticated (ook niet in de standaardrechten voor nieuwe tabellen), geen recht op `platform_log_id_seq`; service_role en supabase_admin ongemoeid (categorie RECHTEN13). **Alleen voor de gemeten PG17.6-productiestand; op PG16 breekt 0036 bewust af** | `0036_overbodige_rechten.sql` (**in productie sinds 15 okt 06:53; vooraf `voor 0036|34|25|true|0`, na `na 0036|0|0|false|0`, md5's gelijk; rooktest geslaagd**; voor- en nacontrole met vingerafdruk incl. kolomrechten) | `rollbacks/0036_rollback.sql` (noodmaatregel: dode rechten terug) | `run(13)` + `tests/rechten-tests.sh` + `prod-rechten-checks.sql` |

Hernummering 10 okt: de tenantswitch werd stap 8 (oude 8–11 → 9–12, bewezen tegen 542 cases); daarna werd restaurant aan/uit stap 9 (9–12 → 10–13, bewezen tegen 693 cases). De migratienummers van de latere stappen liggen pas vast als ze gebouwd worden.

Lokaal bouwen: `PSQL="psql -X -q -h <socket> -p <poort> -U postgres" DB=<naam> TOT=0022|0024|...|0035 [MET_0023=1] [PRODSTAND=1] bash tests/local-build.sh`.
Op PostgreSQL 17 kent `local-build.sh` in de standaardrechten voor nieuwe tabellen ook MAINTAIN toe (zoals de gemeten productiestand); op PostgreSQL 16 bestaat MAINTAIN niet.
Stap 13 testen: op PostgreSQL 17 een basis met `TOT=0035 PRODSTAND=1` (= gemeten productiestand); `rechten-tests.sh` stopt meteen als de inventaris niet gelijk is aan `tests/prod-inventaris-13a.txt`. De vingerafdruk is getoetst op mutatie: als hij kolomrechten van anon en service_role negeert, falen alle 10 kolomtests.
De seed wordt geladen met `session_replication_role = replica` (de guards van stap 7 weigeren anders bijvoorbeeld een direct aangemaakte gesloten rekening).

Werkwijze per stap: (1) eerst op staging/lokaal met `run(stap-1)` → migratie → `run(stap)`; (2) rollback-script op staging
uitproberen; (3) vóór productie `prod-readonly-checks.sql` opnieuw (fingerprints); (4) migratie in productie in één
transactie; (5) `run`-equivalent controles; (6) STOP, rapporteren, nieuwe GO afwachten.

## Regels die blijven gelden

* Geen algemene "if service_role then bypass" in triggers. Een uitzondering is alleen toegestaan voor één benoemde use-case (bv. een smalle functie voor de publieke goedkeuring).
* Service-role-rechten worden pas verlaagd ná een inventaris van wat de routes echt gebruiken (zie architecture.md 13.7).
* Productie is de bron van waarheid; verschillen met de repo worden gerapporteerd, niet zelfstandig gecorrigeerd.
