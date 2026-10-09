# HANDOFF — waar we gebleven zijn (bijgewerkt 9 okt 2026, 20:55)

Doel van dit bestand: elke nieuwe sessie kan hier verder zonder iets te missen. Details staan in `docs/architecture.md` (sectie 13.16, changelog v1.61/v1.62) en `supabase/hardening/README.md`.

## Wat staat LIVE
- Hardening stappen 0–7a + migratie 0022 (approvals_guard aangescherpt) in productie, akkoord.
- **Plan 7b app (commit 5f1966f, v1.0.74)**: een afgewezen bon kan niet gefactureerd worden totdat hij opnieuw is ingediend en goedgekeurd (`generate-invoice` blokkeert vóór elke schrijfactie, fail closed); knop "Opnieuw indienen" en waarschuwing op de rekening.
- Productie-database staat op **migratie 0022**.

## Wat is VOORBEREID maar NIET UITGEVOERD
- **Migratie 0023** (`supabase/migrations/0023_hardening_plan7b_invoice_block.sql`, rollback `supabase/rollbacks/0023_rollback.sql`): extra databaseslot op `closed -> invoiced`. **Niet uitgevoerd in productie; voorlopig laten vallen** (besluit Dick, 9 okt). Gevolg: de app-blokkade is de enige verdediging; directe databasewijzigingen worden niet geweigerd.
- Tests/controles: `tests/preflight-0023-tests.sh` (59 checks), `tests/app-regression/` (t7 173 checks, t8 39 checks), `prod-step7b-checks.sql`, `prod-step7b-preflight-verdict.sql`, 14 gedeelde scenario's (`invoice-block-scenarios.json`), 542 databasecases (541 PASS + 1 OPEN).
- Productiefeiten (read-only gemeten 9 okt): `open_tabs_guard` fingerprint `dc970c3a71212b9b27352ae989d437b1` en `approvals_guard` `d84e5483f3bad1bcb48aa443a2e16644` = de bestandsversies ZONDER `--`-commentaar (kopieerblokken lieten commentaar weg). ACL's en trigger kloppen. Voor 0023 zijn per functie precies twee bekende versies toegestaan (met/zonder commentaar). Kopieerblokken voor productie voortaan EXACT gelijk aan het bestand.
- Deze bestanden staan op branch `plan-7b-0023-voorbereid` (niet op main).

## Volgende stappen (elk met eigen expliciete GO)
1. Live app testen: bon afwijzen → opnieuw indienen → goedkeuren → factureren; en bevestigen dat een afgewezen bon niet gefactureerd kan worden. Werkt de blokkade niet goed: eerst oplossen.
2. **Read-only audit voor meerdere restaurants**: restaurantkoppeling, database, RLS, gebruikersrechten (geen code/migraties/deploys tijdens de audit). Bestaande beveiliging van restaurantgegevens expliciet meenemen.
3. Audit beoordelen → implementatieplan → pas na GO bouwen.
4. Later (alleen met GO): 0023 heropenen (eerst productieverdict, dan kopieerblok), Step 8 (invoices/payments/documents, migratie 0024), platform-admin, restaurantbeheer, UI, integraties, privacy.

## Open punten (niet vergeten)
- TM11/D2 blijft OPEN. D1–D9, UTC-weergavefout, Resend-domeinverificatie, receipt-pagina ververst niet automatisch, gesloten rekening heropenen, creditnota, Step 11 (grants), orphan account D4 (niet verwijderen), `rls_auto_enable()` nooit wijzigen.

## Werkafspraken (kort)
- Audit → plan → expliciete GO per stap → bouwen → lokaal testen → productiecontrole → STOP → gezamenlijke review → nieuwe GO. GPT adviseert/beoordeelt, Claude beslist/implementeert.
- Productieacties als genummerde stappen, EEN stap per bericht, SQL als kopieerblok in de chat; na elke stap stoppen.
- Push alleen op Dick's expliciete "push"; bericht over pushstatus begint met 🟢 KAN GEPUSHT WORDEN (getest + GPT akkoord) of 🟡 NOG NIET PUSHEN. Commit-stijl: `polder <naam> — v1.0.NN — <d> okt 2026, HH:MM`. Laatste versie op main: v1.0.74.
- Geen algemene service_role-bypass in triggers; service_role-rechten niet blind verwijderen (eerst inventaris, Step 11).

## Waar staat wat (bestanden en plekken)

**GitHub: stuctech-eng/polder**
- `main` (commit 5f1966f, v1.0.74): live app incl. 7b-app. Productie (Vercel) bouwt hiervan.
- Branch `plan-7b-0023-voorbereid` (commit 61e01d4+): ALLES wat voorbereid is maar niet live: migratie 0023, rollback, tests, controlequeries, docs, dit bestand. Ophalen: `git fetch origin +refs/heads/plan-7b-0023-voorbereid:refs/remotes/origin/plan-7b-0023-voorbereid`.

**Documentatie**
- `docs/architecture.md`: hoofddocument. Roadmap + volgorde van stappen (sectie 7, "Platformbeheer en privacyfase", "Definitieve volgorde"), audit (sectie 13), hardening per stap (13.x), 13.16 = 0022 + plan 7b (met statusblok), changelog onderaan (v1.61 = 0022, v1.62 = 7b).
- `supabase/hardening/README.md`: tabel van alle hardening-stappen (0–11) en hun status.
- `README.md`: "start here" (verwijst naar dit bestand).

**Database (Supabase)**
- `supabase/migrations/0001…0022`: in productie. `0023`: voorbereid, NIET uitgevoerd. `0024` (Step 8): nog niet gemaakt, geblokkeerd.
- `supabase/rollbacks/`: rollbacks per stap (0022, 0023 aanwezig).
- `supabase/hardening/`: `staging-seed.sql` (testgegevens, twee restaurants A en B), `prod-step7-0022-checks.sql`, `prod-step7b-checks.sql`, `prod-step7b-preflight-verdict.sql` (alleen-lezen productiecontroles).

**Tests (alles lokaal, nooit op productie)**
- `supabase/hardening/tests/`: `00_harness.sql`, `generate_cases.py` → `10_cases.sql` (542 databasecases), `local-build.sh` (bouwt lokale Postgres met migraties), `local-stub.sql`, `local-prodgrants.sql`, `invoice-block-scenarios.json` (14 scenario's), `preflight-0023-tests.sh` (59 checks).
- `supabase/hardening/tests/app-regression/`: app-regressie (t7 = 173 checks, t8 = 39 checks), nep-supabase-client, bouwscripts, README. Paden daarin zijn sandbox-paden (`/home/pgtest`, poort 55432, database `s3`): aanpassen in een nieuwe omgeving.

**App-code die in 7b is aangeraakt**
- `app/api/open-tabs/[id]/generate-invoice/route.ts`, `app/(dashboard)/open-tabs/[id]/page.tsx` en `receipts-section.tsx`, `lib/approval/invoice-blocking.ts`, `lib/approval/resubmit.ts`.

**Buiten de repo**
- Deze sessie: https://claude.ai/code/session_01ByhqutLa8AePgBJi8va3WH (volledige geschiedenis van 0022 en plan 7b, incl. alle GPT-reviews).
- Productie-database: Supabase SQL-editor van Dick (alleen hij kan daar draaien; Claude geeft kopieerblokken, één stap per bericht).
- Claude-geheugen (`/areas/polder.md`): korte statusregels over 7b en de volgende stappen.
- Lokale sandbox (`/home/pgtest`, tijdelijk, mag verdwijnen): alles wat nodig is staat nu in de repo.
