# Polder — Restaurant Business Accounting Platform (Fase 1 / MVP)

Digitale administratie voor zakelijke "op rekening"-bestellingen bij Café Restaurant Polder.
Zie `docs/architecture.md` voor de volledige architectuur (bron van waarheid, sectie 3).

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

- ✅ **Polijstronde (bewerken/verwijderen)**: bedrijf deactiveren/activeren (nooit hard verwijderd — historische facturen blijven intact), open rekening bewerken (tafel/aantal personen) + verwijderen (alleen lege, open rekeningen), bon bewerken (bonnummer) + verwijderen — **geblokkeerd zodra de rekening al gefactureerd is** (audit trail / factuur-integriteit gewaarborgd)

**Belangrijk — extra actie vereist voor Facturatie:**
De PDF-opslag gebruikt een Supabase Storage bucket genaamd `documents` (privé). Als die nog niet bestaat:
1. Supabase → **Storage** → **New bucket**
2. Naam: `documents`, type: **Private**
3. Draai daarna óók `supabase/migrations/0005_storage_policies.sql` — de bucket alleen is niet genoeg, storage heeft een eigen RLS-systeem (zie v1.15)

**Resend SMTP-configuratie (vastgelegd):**
- Host: `smtp.resend.com`, Port: `465`, Username: `resend`
- Sender: `Polder <onboarding@resend.dev>` (testdomein — tijdelijk)
- API key aangemaakt in Resend, ingevuld in Supabase → Authentication → Emails → SMTP Settings

**Bekend openstaand punt (gepland, geen datum):**
- **Eigen domein aanschaffen + verifiëren bij Resend** (~€5-15/jaar). Nodig om naar willekeurige e-mailadressen te kunnen versturen — dus vóór personeel/klanten worden toegevoegd, en sowieso vóór de Facturatie-module (facturen e-mailen). Tot die tijd: gebruik de SQL-noodprocedure hieronder voor wachtwoord-resets.

**Nog te bouwen (na Fase 1):**
- Facturen daadwerkelijk **mailen** naar klanten (wacht op eigen Resend-domein — beslissing bij restauranthouder)
- Factuurstatus bijwerken naar "sent"/"paid" + betalingen registreren
- **Fase 2**: Integration Engine als plugin-systeem (POS-koppelingen, import CSV/Excel), Barcode/QR-scanner

**Handmatige noodprocedure wachtwoord-reset** (zolang Resend nog niet gekoppeld is):
```sql
update auth.users
set encrypted_password = crypt('NieuwWachtwoord', gen_salt('bf'))
where email = 'GEBRUIKER-EMAIL';
```

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
 
