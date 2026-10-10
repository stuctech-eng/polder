# HANDOFF — waar we gebleven zijn (bijgewerkt 10 okt 2026)

Doel van dit bestand: elke nieuwe sessie kan hier verder zonder iets te missen. Details staan in `docs/architecture.md` (13.16 = 0022/7b, **13.17 = fase 1 meerdere restaurants**, roadmap-punt 7 = productdoel en besluiten B1–B6, changelog v1.61–v1.63) en `supabase/hardening/README.md`.

## Wat staat LIVE
- Hardening stappen 0–7a + migratie 0022 (approvals_guard aangescherpt) in productie, akkoord.
- **Plan 7b app (v1.0.74)**: een afgewezen bon kan niet gefactureerd worden totdat hij opnieuw is ingediend en goedgekeurd; knop "Opnieuw indienen".
- Productie-database staat op **migratie 0022**. Productie bevat alleen testdata.

## Wat is GEBOUWD maar NIET UITGEVOERD
- **Migratie 0024 — tenantswitch (fase 1 meerdere restaurants)**: de 15 oude inline-policies lopen via `my_restaurant_id()`, zodat een gedeactiveerde gebruiker nergens meer bij kan en een restaurant later uit te zetten is. Lokaal getest op PostgreSQL 16 én 17 (zie 13.17). **Wacht op GO voor productie.**
  - Bestanden: `supabase/migrations/0024_tenantswitch_inline_policies.sql`, `supabase/rollbacks/0024_rollback.sql`, `supabase/hardening/prod-tenantswitch-checks.sql` (alleen lezen), `supabase/hardening/tests/tenantswitch-tests.sh`.
  - Uitrol: (1) push, (2) migratie als kopieerblok exact gelijk aan het bestand, (3) `prod-tenantswitch-checks.sql` → verwacht 15 × "nieuw", (4) app-test door Dick, (5) STOP.

## Wat is VOORBEREID maar NIET UITGEVOERD
- **Migratie 0023** (plan 7b, databaseslot op `closed -> invoiced`): **voorlopig laten vallen** (besluit Dick, 9 okt). De app-blokkade is de enige verdediging. De harnas-cases van 0023 staan sinds 10 okt op eigen stap 99 (`run(99)` alleen zinvol MET 0023). Heropenen kan later met een eigen GO.

## Volgende stappen (elk met eigen expliciete GO)
1. Fase 1 naar productie (zie hierboven).
2. Platformbasis: `restaurants.status`, `my_restaurant_id()` NULL bij inactief restaurant, `platform_admins` + platform-auditlog (met expliciete `revoke` van anon/authenticated), publieke goedkeuringslink weigeren bij inactief restaurant, app-melding. Eerst inventaris service-role-gebruik.
3. Restaurantbeheer (aanmaken, eigenaar uitnodigen, aan/uit, logboek), featuremodel + configureerbare UI, Default Restaurant, afzendernaam per restaurant, factuurnummer uniek per restaurant.
4. Vóór het eerste echte tweede restaurant: rolrechten (hardening-stappen 9–12), privacyfase, gecontroleerde supporttoegang.

## Open punten (niet vergeten)
- B5: factuurnummer per kalenderjaar opnieuw beginnen of niet.
- TM11/D2 blijft OPEN. D1–D9, UTC-weergavefout, Resend-domeinverificatie, receipt-pagina ververst niet automatisch, gesloten rekening heropenen, creditnota, orphan account D4 (niet verwijderen), `rls_auto_enable()` nooit wijzigen.
- `tsconfig.tsbuildinfo` staat in git (bouwcache; `tsc` wijzigt hem). Later uit git halen.

## Werkafspraken (kort)
- Audit → plan → expliciete GO per stap → bouwen → lokaal testen → productiecontrole → STOP → gezamenlijke review → nieuwe GO.
- **Rollen:** Dick beslist (GO, push). GPT adviseert en beoordeelt resultaten; schrijft geen werkopdrachten. Claude beslist technisch, voert uit, en zegt het als een advies niet wordt overgenomen — met reden en met een oordeel of de controle in verhouding staat tot het risico.
- **Proportioneel:** productie bevat alleen testdata; geen extra controlelagen voor kleine risico's.
- Productieacties als genummerde stappen, EEN stap per bericht, SQL als kopieerblok exact gelijk aan het bestand (met commentaar); na elke stap stoppen.
- Push alleen op Dick's expliciete "push"; bericht over pushstatus begint met 🟢 KAN GEPUSHT WORDEN of 🟡 NOG NIET PUSHEN. Commit-stijl: `polder <naam> — v1.0.NN — <d> okt 2026, HH:MM`. Laatste versie op main: v1.0.75.
- Geen algemene service_role-bypass in triggers; service_role-rechten niet blind verwijderen (eerst inventaris).

## Waar staat wat (bestanden en plekken)

**GitHub: stuctech-eng/polder** — `main` is de enige relevante branch; productie (Vercel) bouwt hiervan. Branch `plan-7b-0023-voorbereid` is overbodig (alles staat op main).

**Documentatie**
- `docs/architecture.md`: hoofddocument (roadmap-punt 7 met productdoel meerdere restaurants en besluiten B1–B6; audit sectie 13; 13.16 = 0022 + 7b; 13.17 = fase 1; changelog).
- `supabase/hardening/README.md`: tabel van alle stappen (0–12, plus 7b) en hun status.
- `README.md`: "start here" (verwijst naar dit bestand).

**Database (Supabase)**
- `supabase/migrations/0001…0022`: in productie. `0023`: voorbereid, niet uitgevoerd. `0024`: gebouwd, wacht op GO.
- `supabase/rollbacks/`: rollbacks per stap (0022, 0023, 0024).
- `supabase/hardening/`: `staging-seed.sql` (testrestaurants A, B en een leeg C), alleen-lezen productiecontroles (`prod-*.sql`).

**Tests (alles lokaal, nooit op productie)**
- `supabase/hardening/tests/`: `00_harness.sql` (incl. `inactief_dml`), `generate_cases.py` → `10_cases.sql` (693 cases), `local-build.sh` (`TOT=0022|0024`, `MET_0023=1`; seed met replica), `tenantswitch-tests.sh` (22 checks), `preflight-0023-tests.sh`, `invoice-block-scenarios.json`.
- `supabase/hardening/tests/app-regression/`: t7 (173 checks; zonder 0023 14 bekende FAIL) en t8 (39). Paden zijn sandboxpaden: aanpassen in een nieuwe omgeving (host, gebruiker, database, repo-pad).
- PostgreSQL 17 lokaal (productie draait 17): `npm install --ignore-scripts @embedded-postgres/linux-x64@17.6.0-beta.15` en de symlinks uit `native/pg-symlinks.json` aanmaken.

**Buiten de repo**
- Sessie 0022/7b (volledige geschiedenis incl. GPT-reviews): https://claude.ai/code/session_01ByhqutLa8AePgBJi8va3WH
- Sessie audit + fase 1 (9–10 okt): https://claude.ai/code/session_01WBujaLa1QhZVP8Ep7tK5mB
- Productie-database: Supabase SQL-editor van Dick (alleen hij kan daar draaien; Claude geeft kopieerblokken, één stap per bericht).
