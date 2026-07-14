# Polder — Restaurant Business Accounting Platform (Fase 1 / MVP)

Digitale administratie voor zakelijke "op rekening"-bestellingen bij Café Restaurant Polder.
Zie `docs/architecture.md` voor de volledige architectuur (bron van waarheid, sectie 3).

## 🚦 Start hier (nieuwe chatsessie / nieuwe Claude-instantie)

**Lees eerst dit bestand volledig, daarna `docs/architecture.md` (vooral sectie 9 Wijzigingshistorie en sectie 10 Status).** Deze twee bestanden samen bevatten alles om zonder verlies verder te werken.

1. **Waar staan we nu:** Fase 1 (MVP) is compleet en end-to-end getest. Een klant-goedgekeurde uitbreiding (Approval Engine + Bedrijfsreferenties) is in uitvoering: Fase A is gebouwd, **Fase B is volledig gepland maar nog niet geïmplementeerd** — zie `docs/architecture.md` sectie 10.7 voor het exacte, goedgekeurde implementatieplan (nieuwe bestanden, database-wijzigingen, risico's).
2. **Eerstvolgende actie:** Fase B bouwen volgens het plan in sectie 10.7 — bouwvolgorde: migratie → interfaces → service → providers → routes → UI → lock-enforcement → events → audit → end-to-end test.
3. **Werkwijze die de hele tijd is aangehouden** (belangrijk om vast te houden):
   - Elke wijziging: lokaal `npx tsc --noEmit` + `npm run build` testen vóórdat een ZIP wordt aangeboden
   - Na elke feature: **zowel** README als `docs/architecture.md` bijwerken in dezelfde stap (wijzigingshistorie ophogen, bijv. v1.23)
   - SQL-migraties altijd **ook als kopieerblok in de chat**, niet alleen in het ZIP-bestand
   - Eén complete ZIP per keer (heel project, nooit losse bestanden) — zie "Bekende valkuil" hieronder
   - Nieuwe API-routes die een parent-ID accepteren: altijd ownership/tenant-isolatie verifiëren (zie v1.20 voor waarom)
   - Nieuwe "vergrendel na actie X"-logica: altijd op **twee niveaus** — UI (verbergen) én API (server-side afdwingen), nooit alleen UI (zie v1.18/v1.19)
4. **Bekende valkuil:** de gebruiker werkt vanaf een iPhone via Working Copy. Bestanden worden soms niet volledig overschreven bij het kopiëren van een ZIP naar de repo — vraag bij twijfel of de gebruiker de volledige, actuele bestandsinhoud terug kan plakken in de chat ter controle (zie v1.4-discussie rond README-synchronisatie).

## Status

**Live omgeving:**
- Productie-URL: `https://polder.vercel.app`
- Supabase-project: `polder` (regio Europe)
- GitHub-repo: `stuctech-eng/polder`

**Belangrijk — acties vereist (in volgorde):**
1. Draai `supabase/migrations/0003_fix_rls_policies.sql` in de Supabase SQL Editor (RLS-fix)
2. Draai `supabase/migrations/0004_fix_grants.sql` in de Supabase SQL Editor (GRANT-fix)

Zonder deze twee migraties toont de app geen data, ook al staat die wel in de database (bekende, opgeloste bugs — zie `docs/architecture.md` v1.4 en v1.5 voor de volledige diagnose).

**Fase 1 voortgang:**
- ✅ Projectstructuur, database-schema (20 tabellen), Event Bus-skeleton
- ✅ Supabase volledig opgezet: schema gedraaid, RLS + automatic RLS aan, eerste gebruiker (owner) gekoppeld aan restaurant "Café Restaurant Polder"
- ✅ Vercel-deploy werkend, environment variables ingesteld
- ✅ Auth-flow volledig werkend: login, middleware route-bescherming, uitloggen
- ✅ Wachtwoord-vergeten flow gebouwd (`/forgot-password`, `/reset-password`) én **volledig gediagnosticeerd**: Supabase + Resend SMTP-koppeling werkt technisch correct (bevestigd: mail komt aan bij `stuctech@gmail.com`). Beperking: Resend's testmodus staat alleen verzending toe naar het eigen Resend-accountadres — dus nog niet bruikbaar voor Ziggo-adressen, personeel of klanten totdat een eigen domein geverifieerd is bij Resend.
- ✅ Bedrijvenbeheer: volledig werkend — overzicht, aanmaken (`/companies/new`), en bekijken/bewerken (`/companies/[id]`), met validatie en zichtbare foutmeldingen
- ✅ Afdelingen, Kostenplaatsen en Projecten: toevoegen + lijst per bedrijf, direct op de bedrijfsdetailpagina
- ✅ Open Rekeningen: openen (met bedrijf/afdeling/kostenplaats/project-koppeling), overzicht met statusfilter (Open/Gesloten/Gefactureerd), sluiten. Navigatie tussen Bedrijven/Rekeningen in de header
- ✅ Receipt Manager: bonnen handmatig invoeren met productregels (dynamisch toevoegen/verwijderen), automatische BTW/totaalberekening, direct gekoppeld aan de open rekening
- ✅ Workflow Engine (basis): facturatieregel per bedrijf instelbaar (frequentie: direct/wekelijks/maandelijks/per project, goedkeuring vereist ja/nee) — wordt gebruikt zodra Facturatie gebouwd is
- ✅ Facturatie: factuur genereren vanuit een gesloten rekening (aggregeert alle gekoppelde bonnen), automatisch factuurnummer, echte PDF-generatie (Document Engine, `pdf-lib`), download via tijdelijke beveiligde link, facturenoverzicht (`/invoices`)
- ✅ Dashboard: open/gesloten rekeningen, omzet deze maand, top bedrijven, recente activiteit — nu de standaard landingspagina na inloggen

**🎉 FASE 1 (MVP) IS COMPLEET.** Het volledige basispad werkt end-to-end: Bedrijf → Open Rekening → Bon → Factuur (met PDF).

- ✅ **Polijstronde (bewerken/verwijderen)**: bedrijf deactiveren/activeren (nooit hard verwijderd — historische facturen blijven intact), open rekening bewerken (tafel/aantal personen) + verwijderen (alleen lege, open rekeningen), bon bewerken (bonnummer) + verwijderen — **geblokkeerd zodra de rekening al gefactureerd is** (audit trail / factuur-integriteit gewaarborgd), inclusief server-side afdwinging (niet alleen UI)
- ✅ **Tenant-isolatie gehard** (v1.20): ownership-checks op alle routes die een gekoppelde parent (bedrijf/rekening) accepteren

**🆕 Klant-goedgekeurde uitbreiding: Approval Engine + Bedrijfsreferenties (zie architecture.md sectie 8)**
- ✅ **Fase A gebouwd**: `company_codes` (generieke routecode/WBS/budgetcode-tabel per bedrijf), verplichte-velden-configuratie per bedrijf (hergebruikt bestaande `configurations`-tabel), schema-voorbereiding voor de uitgebreide statusworkflow (additief, bestaand gedrag ongewijzigd)
- ✅ **Fase A.5 gebouwd — Teambeheer / User Management Module**: medewerkers uitnodigen met eigen account/rol, rol wijzigen, activeren/deactiveren, verwijderen (met bescherming laatste eigenaar + FK-veilige foutafhandeling), centrale autorisatielaag (`lib/user-management/permission-service.ts` — verplicht voor alle nieuwe routes vanaf nu), Dashboard toont nu wie welke actie deed
- ✅ **Fase B gebouwd — Approval Engine core + PIN + Restaurant-bevestigt**: volledige vertical slice werkend end-to-end: bon aanmaken → (indien bedrijf approval vereist) automatisch `pending_approval` → goedkeuren via PIN of "Restaurant bevestigt" → `locked` → geblokkeerd voor wijzigen/verwijderen → factuur weigert bonnen die nog wachten op goedkeuring. Instelbaar per bedrijf op de bedrijfsdetailpagina.
- ✅ **Daily Closing Engine** (`/daily-closing`): dagelijkse operationele controle, los van het Dashboard (dat blijft managementinformatie). Toont omzet vandaag, zakelijke omzet, openstaande rekeningen, bonnen in afwachting van goedkeuring, met eerlijke "n.v.t."-markering voor controles die nog niet mogelijk zijn (afkeuren, kassa-import, betaalmethode-splitsing). Alleen eigenaar/manager kunnen de dag afsluiten.
- ✅ **Definitieve rechtenmatrix + volledige rolbeperking**: elke rol (eigenaar/manager/administratie/bediening/keuken) ziet nu alleen wat bij die rol hoort — zowel in de navigatie als in elke API-route. Bediening ziet bijv. geen omzetcijfers of bedrijvenbeheer, alleen rekeningen/bonnen. Zie `lib/user-management/role-helpers.ts` voor de volledige matrix.
- ✅ **Handleiding** (`/handleiding`): voor iedereen toegankelijk (geen rechten-check op lezen), rolafhankelijk gesorteerd — eigen rol-secties staan open bovenaan, de rest staat er ook maar dichtgeklapt. Bevat ook een rollen/rechten-overzichtstabel.
- ✅ **Navigatie herbouwd** als horizontale scrollbare knoppenbalk (pill-stijl) — schaalt beter nu er meer secties zijn dan op één regel passen.
- ⬜ Fase C (E-mail + QR-provider), Fase D (digitale handtekening — nodig zodra de **bedrijfsklant zelf** moet kunnen goedkeuren, i.p.v. alleen intern personeel via PIN)

**Belangrijk — extra actie vereist voor Facturatie:**
De PDF-opslag gebruikt een Supabase Storage bucket genaamd `documents` (privé). Als die nog niet bestaat:
1. Supabase → **Storage** → **New bucket**
2. Naam: `documents`, type: **Private**
3. Draai daarna óók `supabase/migrations/0005_storage_policies.sql` — de bucket alleen is niet genoeg, storage heeft een eigen RLS-systeem (zie v1.15)

**Belangrijk — actie vereist voor de nieuwe uitbreiding:**
Draai `supabase/migrations/0006_approval_engine_foundation.sql`, `0007_approval_engine_extend.sql`, en `0010_daily_closing.sql` in de Supabase SQL Editor.

**Belangrijk — actie vereist voor Teambeheer:**
1. Draai `supabase/migrations/0008_team_management.sql` in de Supabase SQL Editor
2. Draai daarna óók `supabase/migrations/0009_fix_rls_recursion.sql` — 0008 bevat een kritieke RLS-recursiebug die **alle** schermen breekt (zie v1.24a), 0009 herstelt dit
3. Controleer of `SUPABASE_SERVICE_ROLE_KEY` als environment variable in Vercel staat (bevestigd aanwezig en werkend)

**✅ Fase A.5 volledig bevestigd werkend** (v1.24/v1.24a): teamlijst, uitnodigen (technisch correct — mailbezorging wacht op Resend-domein, zelfde beperking als wachtwoord-reset), rol wijzigen, activeren/deactiveren.

**Resend SMTP-configuratie (vastgelegd):**
- Host: `smtp.resend.com`, Port: `465`, Username: `resend`
- Sender: `Polder <onboarding@resend.dev>` (testdomein — tijdelijk)
- API key aangemaakt in Resend, ingevuld in Supabase → Authentication → Emails → SMTP Settings

**Bekend openstaand punt (gepland, geen datum):**
- **Eigen domein aanschaffen + verifiëren bij Resend** (~€5-15/jaar). Nodig om naar willekeurige e-mailadressen te kunnen versturen — dus vóór personeel/klanten worden toegevoegd, en sowieso vóór de Facturatie-module (facturen e-mailen). Tot die tijd: gebruik de SQL-noodprocedure hieronder voor wachtwoord-resets.

**Zodra de klant akkoord geeft — laatste stappen om écht klaar te zijn:**
1. Domein registreren (~€5-15/jaar)
2. Domein toevoegen bij Resend → SPF/DKIM-records bij de domeinregistrar invoeren
3. Wachten op verificatie (kan enkele uren duren, DNS-propagatie)
4. Supabase SMTP-instellingen bijwerken: afzenderadres van `onboarding@resend.dev` naar bijv. `facturen@restaurantpolder.nl`
5. Testen: wachtwoord-reset, teamuitnodiging, en factuur-mail nogmaals proberen naar een willekeurig (niet-test)adres

Na deze 5 stappen werkt alles wat al gebouwd staat voor iedereen, niet alleen voor het testadres.

**Nog te bouwen (na Fase 1):**
- Facturen daadwerkelijk **mailen** naar klanten (wacht op eigen Resend-domein — beslissing bij restauranthouder)
- Factuurstatus bijwerken naar "sent"/"paid" + betalingen registreren
- **Fase 2**: Integration Engine als plugin-systeem (POS-koppelingen, import CSV/Excel), Barcode/QR-scanner
- **Configureerbare rechtenmatrix**: rechten per rol staan nu vast in code (`role-helpers.ts`). Vervolgstap: verplaatsen naar een databasetabel (`role_permissions`) + scherm op de Team-pagina zodat de eigenaar zelf per rol rechten aan/uit kan zetten, zonder codewijziging. Architectuur is er al op voorbereid (`requireRole()` roept nu een hardcoded check aan die later een database-query wordt).
- **Handleiding** (in-app, alle rollen): stap-voor-stap uitleg per functie, rolbewust — zie aparte planning in `docs/architecture.md` sectie 12.

**Handmatige noodprocedure wachtwoord-reset** (zolang Resend nog niet gekoppeld is):
```sql
update auth.users
set encrypted_password = crypt('NieuwWachtwoord', gen_salt('bf'))
where email = 'GEBRUIKER-EMAIL';
```

## Testaccount aanmaken (zonder Resend-domein)

**Er staat al een werkend testaccount:** `stuctech+test1@gmail.com` (rol: bediening, gekoppeld aan Café Restaurant Polder) — bevestigd werkend, aangemaakt door het "wees"-account van een mislukte uitnodiging (v1.24) alsnog te activeren. Herbruikbaar sjabloon voor nieuwe testaccounts: `supabase/scripts/create-test-account.sql` (geen migratie, handmatig te gebruiken, meerdere keren herhaalbaar met andere waarden).

Handig om een tweede/derde gebruiker te testen (bijv. voor de klant om zelf te proberen) zolang er nog geen eigen maildomein is. Gebruik een Gmail plus-adres (`jouwadres+watdanook@gmail.com` — komt gewoon aan in je normale inbox, geen nep-adres, officiële Gmail-functie).

Inloggen als testgebruiker: privénavigatie-venster → `polder.vercel.app` → `stuctech+test1@gmail.com` / `TestWachtwoord123`.

## Setup (iPhone-first, geen desktop nodig)

1. **Supabase project aanmaken** op supabase.com (via Safari/app)
   - Run de migratie in `supabase/migrations/0001_initial_schema.sql` via de Supabase SQL Editor
   - Kopieer Project URL en anon key naar je Vercel environment variables
2. **GitHub repo**: push deze code (via Working Copy) naar een nieuwe repo
3. **Vercel**: importeer de GitHub repo, zet de environment variables (zie `.env.example`)
4. Vercel deployt automatisch bij elke push vanuit Working Copy

## Lokaal draaien (optioneel, desktop niet verplicht)

```
npm install
cp .env.example .env.local   # vul Supabase-gegevens in
npm run dev
```

## Architectuurprincipes (kort)

- **API-first**: alle logica zit in `app/api/*`, UI is consument
- **Event Bus**: `lib/events` — modules publiceren events, geen directe cross-module calls
- **Database = bron van waarheid**: PostgreSQL/Supabase, nooit de event-log of cache
- **Multi-tenant**: elke tabel heeft `restaurant_id`, afgedwongen via Row Level Security
- **Audit & Activity**: elke belangrijke actie logt naar `activity_log`

Volledige details, governance-principes en de fasering (Fase 1 t/m 5): zie `docs/architecture.md`.
 
