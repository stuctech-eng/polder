# Security hardening — voorbereiding en testharnas (STAP 0)

**Status (10 okt 2026): stappen 0–7 + 0022 in productie; 0023 voorbereid, niet uitgevoerd; stap 8 (tenantswitch, 0024) in productie en akkoord (10 okt); stap 9 (restaurant aan/uit, 0025) in productie en akkoord (10 okt, app v1.0.80); platformbeheer (0026 + 0027) gebouwd en lokaal getest, wacht op GO.** Niets in deze map wijzigt productie zonder expliciete GO.
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
| `prod-platform-beheerder.sql` | **Productie** — WIJZIGT (alleen met GO) | Voegt stuctech@gmail.com toe als platformbeheerder; weigert een account met restaurantprofiel |

## Testharnas gebruiken

```sql
-- na staging-seed.sql, 00_harness.sql en 10_cases.sql:
select * from hardening_test.summary(0);                       -- huidige stand: alles PASS
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
| — | **Platformbeheer**: `platform_admins`, `platform_log`, `is_platform_admin()`; actiefuncties met logregel in één transactie (categorie PLATFORM, stap 0: geldt altijd vanaf 0027) | `0026_platformbeheer.sql` + `0027_platform_acties.sql` + app (**gebouwd en lokaal getest op PG16 + PG17; wacht op GO**) | `rollbacks/0027_rollback.sql`, dan `0026_rollback.sql` (eerst app terug) | `run(9)` (PLATFORM 27/27) + `tests/platform-tests.sh` + app-test t10 + `prod-platform-checks.sql` |
| 10 | H4b invoices/payments/documents (rolrechten) | gepland | gepland | `run(10)` |
| 11 | H4c + H4d dagafsluiting/stamdata/settings/plugins | gepland | gepland | `run(11)` |
| 12 | H10 PIN-geheimen | gepland (+ app) | gepland | `run(12)` |
| 13 | H8b definitieve least privilege + eindtest | gepland | gepland | `run(13)` + her-audit |

Hernummering 10 okt: de tenantswitch werd stap 8 (oude 8–11 → 9–12, bewezen tegen 542 cases); daarna werd restaurant aan/uit stap 9 (9–12 → 10–13, bewezen tegen 693 cases). De migratienummers van de latere stappen liggen pas vast als ze gebouwd worden.

Lokaal bouwen: `PSQL="psql -X -q -h <socket> -p <poort> -U postgres" DB=<naam> TOT=0022|0024 [MET_0023=1] bash tests/local-build.sh`.
De seed wordt geladen met `session_replication_role = replica` (de guards van stap 7 weigeren anders bijvoorbeeld een direct aangemaakte gesloten rekening).

Werkwijze per stap: (1) eerst op staging/lokaal met `run(stap-1)` → migratie → `run(stap)`; (2) rollback-script op staging
uitproberen; (3) vóór productie `prod-readonly-checks.sql` opnieuw (fingerprints); (4) migratie in productie in één
transactie; (5) `run`-equivalent controles; (6) STOP, rapporteren, nieuwe GO afwachten.

## Regels die blijven gelden

* Geen algemene "if service_role then bypass" in triggers. Een uitzondering is alleen toegestaan voor één benoemde use-case (bv. een smalle functie voor de publieke goedkeuring).
* Service-role-rechten worden pas verlaagd ná een inventaris van wat de routes echt gebruiken (zie architecture.md 13.7).
* Productie is de bron van waarheid; verschillen met de repo worden gerapporteerd, niet zelfstandig gecorrigeerd.
