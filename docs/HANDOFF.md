# HANDOFF — waar we gebleven zijn (bijgewerkt 17 okt 2026)

Doel van dit bestand: elke nieuwe sessie kan hier verder zonder iets te missen. Details staan in `docs/architecture.md` (13.16 = 0022/7b, **13.17 = fase 1 meerdere restaurants**, **13.18 = fase 2 restaurant aan/uit**, **13.19 = platformbeheer**, **13.20 = mail-links**, **13.21 = fase 4 modules**, roadmap-punt 7 = productdoel en besluiten B1–B6, changelog v1.61–v1.67) en `supabase/hardening/README.md`.

## Wat staat LIVE
- Hardening stappen 0–7a + migratie 0022 (approvals_guard aangescherpt) in productie, akkoord.
- **Plan 7b app (v1.0.74)**: een afgewezen bon kan niet gefactureerd worden totdat hij opnieuw is ingediend en goedgekeurd; knop "Opnieuw indienen".
- **Fase 1 meerdere restaurants — tenantswitch (migratie 0024, v1.0.77)**: in productie sinds 10 okt 12:38, akkoord (controle 15 × "nieuw", app-test geslaagd). Een gedeactiveerde gebruiker kan nu in geen enkele tabel meer iets zien of wijzigen.
- **Fase 2 meerdere restaurants — restaurant aan/uit (migratie 0025, v1.0.80)**: in productie sinds 10 okt 16:28 (migratie) / 16:29 (app). Controle 0025/0025/ja/ja/0/false/leeg; app-test door Dick geslaagd (normaal werken; restaurant uit → inlogscherm met "Dit restaurant staat uit"; weer aan → werkt). Aan/uit gaat voorlopig met SQL: `update public.restaurants set is_active = false|true where id = '…';` (productie heeft één restaurant: Café Restaurant Polder, `374a9aa4-a34e-4ec0-ab24-78988a38b0fb`).
- **Platformbeheer (migraties 0026 + 0027, v1.0.83)**: in productie sinds 10 okt, akkoord 11 okt. Beheerscherm `/platform` (inloggen als stuctech@gmail.com, apart account zonder restaurantprofiel): restaurants zien, aanmaken, aan/uit, eerste eigenaar uitnodigen, logboek. Beheeractie + logregel in één transactie. Beheerder toevoegen alleen met SQL (`prod-platform-beheerder.sql`).
- **Mail-links (v1.0.84/v1.0.85)**: wachtwoord herstellen en uitnodigingen werken in elke browser (server vraagt de herstelmail aan; /reset-password leest de sessie uit de link). Geen aanpassing in Supabase nodig.
- **Fase 4 — modules per restaurant (migraties 0028–0030, v1.0.88)**: in productie sinds 11 okt, akkoord 12 okt. In het beheerscherm per restaurant Dagafsluiting, Betalingen registreren en Goedkeuring aan/uit (alleen de platformbeheerder; logregel per wijziging). Uit = verborgen in menu/pagina's, routes geven 403 en de databasewacht weigert schrijfacties. Alle modules staan standaard aan. Productie `guards_md5` = `287f55d538eeb47386154595baf42dee` (controle met `prod-modules-checks.sql`).
- **Hardening stap 10 — rolrechten facturen (migraties 0031–0032, app v1.0.91)**: in productie sinds 13 okt 15:52. Controle vooraf 0030/4/4/0/leeg, na 0032 0032/11/0/3/true; `guards_md5` (287f55d5…), `module_wacht_md5` (1d1de1f5…) en `modules_md5` (6fa1b0af…) vóór en na gelijk. Rooktest door Dick als owner geslaagd (factuur 2026-0011 gemaakt, drie deelbetalingen, volledig betaald, dashboard zichtbaar). Alleen owner/administratie maken en wijzigen facturen en betalingen; niemand wist ze; betaald is eindstand. Zie architecture 13.22.
- **Hardening stap 11 — rolrechten dagafsluiting, bedrijven, instellingen (migraties 0033–0034, v1.0.94)**: in productie sinds 13 okt 17:35. Controle vooraf 0032/12/12/12/12/leeg, na 0033 0033/12/19/6/6, na 0034 0034/12/22/0/0/true; `guards_md5` (a324f688…), `module_wacht_md5` (1d1de1f5…), `modules_md5` (6fa1b0af…) en `overige_md5` (1a66865a…) telkens gelijk. Rooktest door Dick als owner: "alles lijkt oké" (dagafsluiting-pagina leesbaar). Geen ALL-policy meer in de database. email_settings bestaat in productie niet (eerste controle gaf 12 i.p.v. 13; 0034, rollback en leesblok daarop aangepast vóór uitvoering). Zie architecture 13.23.
- **Hardening stap 12 — PIN-gegevens (app v1.0.96 + migratie 0035)**: app live 13 okt 18:56, migratie 18:59. Controle vooraf 0034|true|true|10|false|true|true, na 0035 0035|true|false|8|false|true|true; vijf md5's (guards a324f688…, module_wacht 1d1de1f5…, modules 6fa1b0af…, policies c25cd844…, rechten 99e393ef…) gelijk. Rooktest door Dick geslaagd (PIN instellen, opslaan zonder PIN, foute PIN geweigerd, juiste PIN goedgekeurd). Medewerkers kunnen pin_hash/pin_salt niet meer lezen; de server leest ze alleen in de goedkeurroute. Zie architecture 13.24.
- **Hardening stap 13 — overbodige rechten (migratie 0036, push v1.0.98)**: in productie 15 okt 06:53. Controle vooraf `voor 0036|34|25|true|0` (vingerafdruk 469416b6…), na `na 0036|0|0|false|0` (afd46a82…); drie md5's (service 36f1d931…, supabase_admin a7e1a474…, policies+functies c25cd844…def3072f…) gelijk. Rooktest door Dick geslaagd. Medewerkers (authenticated) hebben nu alleen nog tabelrechten waar een policy bij hoort; geen MAINTAIN meer voor anon/authenticated, ook niet op nieuwe tabellen. Alleen voor de gemeten PG17.6-stand (op PG16 breekt 0036 bewust af). Zie architecture 13.25.
- **Hardening stap 14a — PIN-pogingen en PIN in de database (migraties 0037–0042, push A v1.0.100 + app push B v1.0.101)**: in productie 16 okt. Volgorde: 0037–0041 (elk met nacontrole) → app → 0042. Nulmeting `0036|000000|true|0`, `bestaand_md5` 010fecff… telkens gelijk; eindstand `0042|111111|true|3`. Rooktest door Dick geslaagd: PIN (fout en juist), QR/e-mail-link en restaurant_confirms. Hooguit 5 PIN-pogingen per 15 min per bedrijf, daarna 15 min blokkade; de database keurt een PIN-bon alleen goed met een juiste, verse reservering; de methode geldt per bon; indienen gaat in één transactie (`bon_indienen`). Zie architecture 13.26.
- **Rekeningpagina ververst zichzelf (v1.0.103, 16 okt)**: zolang een bon wacht op QR- of e-mailgoedkeuring elke 5 s (alleen als de app zichtbaar is); rooktest door Dick geslaagd. Zie architecture v1.74.
- **Stap 14b — factureren alleen met goedkeuring (v1.0.105, 16 okt, alleen app)**: vereist het bedrijf goedkeuring, dan weigert facturatie elke bon die niet goedgekeurd is, ook een nooit ingediende; scherm toont "Nog niet ingediend" + knop Indienen. Rooktest door Dick geslaagd (weigering met bonnaam, indienen, goedkeuren, factureren). Sluiten van de rekening blijft bewust toegestaan. Zie architecture v1.75.
- **Bon toevoegen: duidelijke melding (v1.0.107, 16 okt)**: in plaats van "Validatiefout" de eerste fout in het Nederlands met regelnummer (bv. "Productregel 1: vul een omschrijving in."); app-test t20; door Dick getest.
- **Stap 14c — handtekening van de klant (migraties 0043–0048, push A v1.0.109 + app push B v1.0.110)**: in productie 17 okt. Volgorde: push A (alleen database, controleblokken, tests, documentatie) → 0043 t/m 0048 (één per stap, na elke stap controleblok A en vanaf 0047 ook F) → push B (app). Nulmeting `0042|000000|true|0|d84e54,9d3540`, `bestaand_md5` f911b041… bij elke stap gelijk; eindstand `0048|111111|true|2|f09a66,50feb6`; blok F na 0047 en 0048 `GELIJK` (083a2f1e…), `kenmerken_ok` true, recht eerst alleen postgres, na 0048 ook authenticated. Rooktest door Dick geslaagd: tekenen door de klant, en PIN, QR en restaurant bevestigt werken nog; een vastgelopen e-mailbon (geen Resend ingesteld, mail nooit verstuurd) losgemaakt via de normale goedkeuringslink uit de database. Module Handtekening staat standaard uit; de platformbeheerder zet hem per restaurant aan. Zie architecture 13.27.
- Productie-database staat op **migratie 0048** (0023 niet uitgevoerd). Productie bevat alleen testdata.
- Vercel-functieregio is op 16 okt door Dick gelijkgezet aan de Supabase-regio (daarvoor standaard VS; elke databaseopdracht ging over de oceaan).

## Wat is LOKAAL GEBOUWD maar NOG NIET GEPUSHT

## Wat is VOORBEREID maar NIET UITGEVOERD
- **Migratie 0023** (plan 7b, databaseslot op `closed -> invoiced`): **voorlopig laten vallen** (besluit Dick, 9 okt). De app-blokkade is de enige verdediging. De harnas-cases van 0023 staan sinds 10 okt op eigen stap 99 (`run(99)` alleen zinvol MET 0023). Heropenen kan later met een eigen GO.


## Volgende stappen (elk met eigen expliciete GO)
1. Default Restaurant, afzendernaam per restaurant, factuurnummer uniek per restaurant.
2. Vóór het eerste echte tweede restaurant: rolrechten (stap 10–13 en 14a in productie), privacyfase, gecontroleerde supporttoegang.
3. (Optioneel, later) 14b ook in de database afdwingen (zoals 0023): nu alleen in de app; besloten 16 okt: optie A volstaat zolang productie alleen testdata bevat.
   Besluiten 12 okt: D6 = draft -> paid blijft toegestaan; ongebruikte tabellen (integration_plugins, email_settings, notifications) in stap 11 helemaal dicht voor restaurantrollen; volgorde 10 → 11 → 12 → 13.

## Open punten (niet vergeten)
- B5: factuurnummer per kalenderjaar opnieuw beginnen of niet.
- Stap 14c: een opgeslagen handtekening is nog niet terug te zien in de app (staat wel bij de goedkeuringsregel in de database: naam, handtekening, tijdstip, medewerker, vingerafdruk). Een scherm om hem achteraf te bekijken is bewust nog niet gebouwd.
- Stap 14c: een handtekeningbon kan in de app niet worden afgewezen (geen afwijsknop; bewust niet gebouwd). Herstel alleen door de beheerder in de SQL-editor met `set local role service_role` (zie architecture 13.27; in productie nog niet uitgeprobeerd).
- Stap 14c: na het tekenen kan het bedrijf van de rekening nog worden gewijzigd (geldt al voor alle goedkeuringsmethoden; tijdens het tekenen is de rekening wel vergrendeld).
- Stap 14c: de PNG-controle (`png_geldig`) controleert begin (PNG-handtekening en IHDR), afmetingen en einde (IEND), maar niet de controlegetallen en beeldgegevens in het midden; een beschadigde PNG met juist begin en eind wordt aangenomen (de handtekening wordt nergens getoond).
- E-mailgoedkeuring zonder Resend (`RESEND_API_KEY` niet ingesteld): de mail wordt niet verstuurd, maar het scherm zegt toch "Goedkeuringsmail verstuurd" (de waarschuwing van de server wordt bij een wachtende bon niet getoond). Bestond al vóór 14c. Losmaken: link opzoeken met `select 'https://polder.vercel.app/approve/' || verification_code from approvals where status = 'pending' and method = 'email';` en openen (goedkeuren of afwijzen).
- Een e-mail- of QR-bon kan in de app zelf niet worden afgewezen of opnieuw verstuurd; alleen via de link. Bestond al vóór 14c.
- Bestaand probleem (alle goedkeuringsmethoden, buiten 14c; eigen audit nodig): tijdens een goedkeuring kan via de API nog een extra wachtende goedkeuringsregel worden toegevoegd (de bewaking van 0022 kijkt naar de status van vóór het wachten). Gevolg: vergrendelde bon met een extra wachtende regel; het scherm toont dan "administratie niet volledig".
- Testharnas: een mislukte voorbereiding (setup) van een case telt nu als "geweigerd". Stap-11-cases zijn gecontroleerd (geen enkele slaagt daardoor); het harnas zelf verbeteren is een apart klein punt.
- Na stap 13 (in productie 15 okt) blijven de standaardrechten van supabase_admin ruim (niet door ons aan te passen; geldt alleen voor objecten die supabase_admin aanmaakt).
- Productkeuze (later): dagafsluiting telt omzet uit bonnen van die dag (bondatum), niet uit facturen. Op 13 okt dus €0,00 bij 2 facturen van oudere bonnen; geen fout.
- Na goedkeuren: mislukte logregels (domain_events, activity_log) worden niet gemeld (bestond al zo).
- 13 okt 19:04: één POST /api/open-tabs duurde 11,4 s en gaf 500 "Internal server error." (niets opgeslagen; daarna werkte het weer; geen hangende transacties). Vermoedelijk tijdelijke traagheid Supabase/Vercel. Twee testrekeningen (Demo Kantoor BV, 19:03, zonder tafel) staan nog open. Bij herhaling: Vercel- en Supabase-logs bekijken.
- TM11/D2 blijft OPEN. D1–D9, UTC-weergavefout, Resend-domeinverificatie, gesloten rekening heropenen, creditnota, orphan account D4 (niet verwijderen), `rls_auto_enable()` nooit wijzigen.
- Testrestaurant "Test restaurant" staat in productie (testdata, aangemaakt via het beheerscherm).
- "Eigenaar uitnodigen" is nog niet in productie getest (mail valt onder de Resend-testlimiet).
- Zijtak `plan-7b-0023-voorbereid` op GitHub: alle bestanden staan ook op main, maar de zijtak bevat de enige kopie van de oude commitgeschiedenis (v1.0.2–v1.0.74; main begint bij v1.0.76). Bewust laten staan (archief). De rode "Error" in Vercel hoort bij een oude preview van die tak en is onschuldig.
- `tsconfig.tsbuildinfo` staat in git (bouwcache; `tsc` wijzigt hem). Later uit git halen.

## Werkafspraken (kort)
- Audit → plan → expliciete GO per stap → bouwen → lokaal testen → productiecontrole → STOP → gezamenlijke review → nieuwe GO.
- **Rollen:** Dick beslist (GO, push). GPT adviseert en beoordeelt resultaten; schrijft geen werkopdrachten. Claude beslist technisch, voert uit, en zegt het als een advies niet wordt overgenomen — met reden en met een oordeel of de controle in verhouding staat tot het risico.
- **Proportioneel:** productie bevat alleen testdata; geen extra controlelagen voor kleine risico's.
- Bij migraties met een controleblok: na elke migratiestap eerst het controleblok uitvoeren en beoordelen, pas daarna de volgende stap (14c: `prod-teken14c-checks.sql` en vanaf 0047 ook `prod-teken14c-functie.sql`).
- Productieacties als genummerde stappen, EEN stap per bericht, SQL als kopieerblok exact gelijk aan het bestand (met commentaar); na elke stap stoppen.
- **Kopieerblokken kort houden (≤ ±3.000 tekens):** plakken in de Supabase-editor op de iPhone kapte een blok van 9.300 tekens na ±3.800 tekens af (10 okt). Een afgekapt blok geeft een syntaxfout en voert niets uit. Langere migraties compact schrijven (één DO-blok) of in losse, elk op zichzelf veilige blokken.
- Push alleen op Dick's expliciete "push"; bericht over pushstatus begint met 🟢 KAN GEPUSHT WORDEN of 🟡 NOG NIET PUSHEN. Commit-stijl: `polder <naam> — v1.0.NN — <d> okt 2026, HH:MM`. Laatste versie op main: v1.0.107 (+ docs).
- Geen algemene service_role-bypass in triggers; service_role-rechten niet blind verwijderen (eerst inventaris).

## Waar staat wat (bestanden en plekken)

**GitHub: stuctech-eng/polder** — `main` is de enige relevante branch; productie (Vercel) bouwt hiervan. Branch `plan-7b-0023-voorbereid` = archief van de oude commitgeschiedenis (niet verwijderen zonder akkoord).

**Documentatie**
- `docs/architecture.md`: hoofddocument (roadmap-punt 7 met productdoel meerdere restaurants en besluiten B1–B6; audit sectie 13; 13.16 = 0022 + 7b; 13.17 = fase 1; changelog).
- `supabase/hardening/README.md`: tabel van alle stappen (0–13, plus 7b) en hun status.
- `README.md`: "start here" (verwijst naar dit bestand).

**Database (Supabase)**
- `supabase/migrations/0001…0022`: in productie. `0023`: voorbereid, niet uitgevoerd. `0024` en `0025`: in productie (10 okt). `0026` en `0027`: in productie (10 okt). `0028`–`0030`: in productie (11 okt). `0031`–`0042`: in productie (0037–0042 sinds 16 okt). `0043`–`0048` (14c): in productie (17 okt).
- `supabase/rollbacks/`: rollbacks per stap (0022–0048).
- `supabase/hardening/`: `staging-seed.sql` (testrestaurants A, B en een leeg C), alleen-lezen productiecontroles (`prod-*.sql`).

**Tests (alles lokaal, nooit op productie)**
- `supabase/hardening/tests/`: `00_harness.sql` (incl. `inactief_dml`), `generate_cases.py` → `10_cases.sql` (693 cases), `local-build.sh` (`TOT=0022|0024`, `MET_0023=1`; seed met replica), `tenantswitch-tests.sh` (22 checks), `preflight-0023-tests.sh`, `invoice-block-scenarios.json`.
- `supabase/hardening/tests/app-regression/`: t7 (173 checks; zonder 0023 14 bekende FAIL) t/m t22 (t21/t22 = stap 14c); zie de README daar. Paden zijn sandboxpaden: aanpassen in een nieuwe omgeving (host, gebruiker, database, repo-pad).
- `supabase/hardening/tests/pinpogingen-tests.sh`: stap 14a (126 checks, PG16 en PG17).
- `supabase/hardening/tests/handtekening-tests.sh`: stap 14c (165 checks, PG16 en PG17; basis = database t/m 0042).
- PostgreSQL 17 lokaal (productie draait 17): `npm install --ignore-scripts @embedded-postgres/linux-x64@17.6.0-beta.15` en de symlinks uit `native/pg-symlinks.json` aanmaken.

**Buiten de repo**
- Sessie 0022/7b (volledige geschiedenis incl. GPT-reviews): https://claude.ai/code/session_01ByhqutLa8AePgBJi8va3WH
- Sessie audit + fase 1 (9–10 okt): https://claude.ai/code/session_01WBujaLa1QhZVP8Ep7tK5mB
- Productie-database: Supabase SQL-editor van Dick (alleen hij kan daar draaien; Claude geeft kopieerblokken, één stap per bericht).
