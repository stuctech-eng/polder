# HANDOFF — waar we gebleven zijn (bijgewerkt 10 okt 2026)

Doel van dit bestand: elke nieuwe sessie kan hier verder zonder iets te missen. Details staan in `docs/architecture.md` (13.16 = 0022/7b, **13.17 = fase 1 meerdere restaurants**, **13.18 = fase 2 restaurant aan/uit**, **13.19 = platformbeheer**, roadmap-punt 7 = productdoel en besluiten B1–B6, changelog v1.61–v1.65) en `supabase/hardening/README.md`.

## Wat staat LIVE
- Hardening stappen 0–7a + migratie 0022 (approvals_guard aangescherpt) in productie, akkoord.
- **Plan 7b app (v1.0.74)**: een afgewezen bon kan niet gefactureerd worden totdat hij opnieuw is ingediend en goedgekeurd; knop "Opnieuw indienen".
- **Fase 1 meerdere restaurants — tenantswitch (migratie 0024, v1.0.77)**: in productie sinds 10 okt 12:38, akkoord (controle 15 × "nieuw", app-test geslaagd). Een gedeactiveerde gebruiker kan nu in geen enkele tabel meer iets zien of wijzigen.
- **Fase 2 meerdere restaurants — restaurant aan/uit (migratie 0025, v1.0.80)**: in productie sinds 10 okt 16:28 (migratie) / 16:29 (app). Controle 0025/0025/ja/ja/0/false/leeg; app-test door Dick geslaagd (normaal werken; restaurant uit → inlogscherm met "Dit restaurant staat uit"; weer aan → werkt). Aan/uit gaat voorlopig met SQL: `update public.restaurants set is_active = false|true where id = '…';` (productie heeft één restaurant: Café Restaurant Polder, `374a9aa4-a34e-4ec0-ab24-78988a38b0fb`).
- Productie-database staat op **migratie 0025** (0023 niet uitgevoerd). Productie bevat alleen testdata.

## Wat is GEBOUWD maar NIET gepusht / NIET in productie
- **Platformbeheer (migraties 0026 + 0027, beheerscherm `/platform`)**: lokaal getest op PG16 en PG17 (zie architecture 13.19). Beheerder = apart account stuctech@gmail.com (zonder restaurantprofiel). Beheeractie + logregel in één transactie. Uitrol in DEZE volgorde: push A (database/tests/docs) → `prod-platform-checks.sql` → migratie 0026 → migratie 0027 → leesblok → `prod-platform-beheerder.sql` → push B (app) → app-test.

## Wat is VOORBEREID maar NIET UITGEVOERD
- **Migratie 0023** (plan 7b, databaseslot op `closed -> invoiced`): **voorlopig laten vallen** (besluit Dick, 9 okt). De app-blokkade is de enige verdediging. De harnas-cases van 0023 staan sinds 10 okt op eigen stap 99 (`run(99)` alleen zinvol MET 0023). Heropenen kan later met een eigen GO.

## Volgende stappen (elk met eigen expliciete GO)
1. Platformbeheer naar productie — gebouwd, zie hierboven.
2. Featuremodel + configureerbare UI, Default Restaurant, afzendernaam per restaurant, factuurnummer uniek per restaurant.
3. Vóór het eerste echte tweede restaurant: rolrechten (hardening-stappen 10–13), privacyfase, gecontroleerde supporttoegang.

## Open punten (niet vergeten)
- B5: factuurnummer per kalenderjaar opnieuw beginnen of niet.
- TM11/D2 blijft OPEN. D1–D9, UTC-weergavefout, Resend-domeinverificatie, receipt-pagina ververst niet automatisch, gesloten rekening heropenen, creditnota, orphan account D4 (niet verwijderen), `rls_auto_enable()` nooit wijzigen.
- `tsconfig.tsbuildinfo` staat in git (bouwcache; `tsc` wijzigt hem). Later uit git halen.

## Werkafspraken (kort)
- Audit → plan → expliciete GO per stap → bouwen → lokaal testen → productiecontrole → STOP → gezamenlijke review → nieuwe GO.
- **Rollen:** Dick beslist (GO, push). GPT adviseert en beoordeelt resultaten; schrijft geen werkopdrachten. Claude beslist technisch, voert uit, en zegt het als een advies niet wordt overgenomen — met reden en met een oordeel of de controle in verhouding staat tot het risico.
- **Proportioneel:** productie bevat alleen testdata; geen extra controlelagen voor kleine risico's.
- Productieacties als genummerde stappen, EEN stap per bericht, SQL als kopieerblok exact gelijk aan het bestand (met commentaar); na elke stap stoppen.
- **Kopieerblokken kort houden (≤ ±3.000 tekens):** plakken in de Supabase-editor op de iPhone kapte een blok van 9.300 tekens na ±3.800 tekens af (10 okt). Een afgekapt blok geeft een syntaxfout en voert niets uit. Langere migraties compact schrijven (één DO-blok) of in losse, elk op zichzelf veilige blokken.
- Push alleen op Dick's expliciete "push"; bericht over pushstatus begint met 🟢 KAN GEPUSHT WORDEN of 🟡 NOG NIET PUSHEN. Commit-stijl: `polder <naam> — v1.0.NN — <d> okt 2026, HH:MM`. Laatste versie op main: v1.0.81.
- Geen algemene service_role-bypass in triggers; service_role-rechten niet blind verwijderen (eerst inventaris).

## Waar staat wat (bestanden en plekken)

**GitHub: stuctech-eng/polder** — `main` is de enige relevante branch; productie (Vercel) bouwt hiervan. Branch `plan-7b-0023-voorbereid` is overbodig (alles staat op main).

**Documentatie**
- `docs/architecture.md`: hoofddocument (roadmap-punt 7 met productdoel meerdere restaurants en besluiten B1–B6; audit sectie 13; 13.16 = 0022 + 7b; 13.17 = fase 1; changelog).
- `supabase/hardening/README.md`: tabel van alle stappen (0–12, plus 7b) en hun status.
- `README.md`: "start here" (verwijst naar dit bestand).

**Database (Supabase)**
- `supabase/migrations/0001…0022`: in productie. `0023`: voorbereid, niet uitgevoerd. `0024` en `0025`: in productie (10 okt). `0026`/`0027`: gebouwd, niet uitgevoerd.
- `supabase/rollbacks/`: rollbacks per stap (0022–0027).
- `supabase/hardening/`: `staging-seed.sql` (testrestaurants A, B en een leeg C), alleen-lezen productiecontroles (`prod-*.sql`).

**Tests (alles lokaal, nooit op productie)**
- `supabase/hardening/tests/`: `00_harness.sql` (incl. `inactief_dml`), `generate_cases.py` → `10_cases.sql` (693 cases), `local-build.sh` (`TOT=0022|0024`, `MET_0023=1`; seed met replica), `tenantswitch-tests.sh` (22 checks), `preflight-0023-tests.sh`, `invoice-block-scenarios.json`.
- `supabase/hardening/tests/app-regression/`: t7 (173 checks; zonder 0023 14 bekende FAIL) en t8 (39). Paden zijn sandboxpaden: aanpassen in een nieuwe omgeving (host, gebruiker, database, repo-pad).
- PostgreSQL 17 lokaal (productie draait 17): `npm install --ignore-scripts @embedded-postgres/linux-x64@17.6.0-beta.15` en de symlinks uit `native/pg-symlinks.json` aanmaken.

**Buiten de repo**
- Sessie 0022/7b (volledige geschiedenis incl. GPT-reviews): https://claude.ai/code/session_01ByhqutLa8AePgBJi8va3WH
- Sessie audit + fase 1 (9–10 okt): https://claude.ai/code/session_01WBujaLa1QhZVP8Ep7tK5mB
- Productie-database: Supabase SQL-editor van Dick (alleen hij kan daar draaien; Claude geeft kopieerblokken, één stap per bericht).
