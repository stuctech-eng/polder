# Security hardening — voorbereiding en testharnas (STAP 0)

**Status: voorbereiding (Stap 0) afgerond; Stap 1 geschreven en lokaal getest.** Niets in deze map wijzigt productie. Er is **geen GO** voor hardening-stap 1 t/m 11.
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
| 5 | H7 cross-reference integriteit | `0019_hardening_crossref.sql` | `rollbacks/0019_rollback.sql` | `run(5)` |
| 6 | H6 storage | `0020_hardening_storage.sql` (+ app: `upsert:false`) | `rollbacks/0020_rollback.sql` | `run(6)` |
| 7 | H4a open_tabs/receipts/approvals | `0021_hardening_tabs_receipts.sql` | `rollbacks/0021_rollback.sql` | `run(7)` |
| 8 | H4b invoices/payments/documents | `0022_hardening_invoices.sql` | `rollbacks/0022_rollback.sql` | `run(8)` |
| 9 | H4c + H4d dagafsluiting/stamdata/settings/plugins | `0023_hardening_master_data.sql` | `rollbacks/0023_rollback.sql` | `run(9)` |
| 10 | H10 PIN-geheimen | `0024_hardening_pin_secrets.sql` (+ app) | `rollbacks/0024_rollback.sql` | `run(10)` |
| 11 | H8b definitieve least privilege + eindtest | `0025_hardening_final_privileges.sql` | `rollbacks/0025_rollback.sql` | `run(11)` + her-audit |

Werkwijze per stap: (1) eerst op staging/lokaal met `run(stap-1)` → migratie → `run(stap)`; (2) rollback-script op staging
uitproberen; (3) vóór productie `prod-readonly-checks.sql` opnieuw (fingerprints); (4) migratie in productie in één
transactie; (5) `run`-equivalent controles; (6) STOP, rapporteren, nieuwe GO afwachten.

## Regels die blijven gelden

* Geen algemene "if service_role then bypass" in triggers. Een uitzondering is alleen toegestaan voor één benoemde use-case (bv. een smalle functie voor de publieke goedkeuring).
* Service-role-rechten worden pas verlaagd ná een inventaris van wat de routes echt gebruiken (zie architecture.md 13.7).
* Productie is de bron van waarheid; verschillen met de repo worden gerapporteerd, niet zelfstandig gecorrigeerd.
