# Polder — Restaurant Business Accounting Platform (Fase 1 / MVP)

Digitale administratie voor zakelijke "op rekening"-bestellingen bij Café Restaurant Polder.
Zie `docs/architecture.md` voor de volledige architectuur (bron van waarheid, sectie 3).

## Status

**Live omgeving:**
- Productie-URL: `https://polder.vercel.app`
- Supabase-project: `polder` (regio Europe)
- GitHub-repo: `stuctech-eng/polder`

**Fase 1 voortgang:**
- ✅ Projectstructuur, database-schema (20 tabellen), Event Bus-skeleton
- ✅ Supabase volledig opgezet: schema gedraaid, RLS + automatic RLS aan, eerste gebruiker (owner) gekoppeld aan restaurant "Café Restaurant Polder"
- ✅ Vercel-deploy werkend, environment variables ingesteld
- ✅ Auth-flow volledig werkend: login, middleware route-bescherming, uitloggen
- ✅ Wachtwoord-vergeten flow gebouwd (`/forgot-password`, `/reset-password`) — **werkt technisch correct** (bevestigd in Supabase Auth Logs: `/recover` + `mail.send` succesvol), maar de e-mail komt niet betrouwbaar aan bij Ziggo/KPN-achtige providers. Oorzaak: Supabase's gratis ingebouwde e-mailservice, geen codefout.
- ✅ Bedrijvenbeheer: API-route + overzichtspagina (leeg, want "Nieuw bedrijf"-formulier nog niet gebouwd)

**Bekend openstaand punt (gepland voor morgen):**
- **Resend koppelen** als eigen SMTP-provider in Supabase (Authentication → Settings → SMTP Settings). Dit lost het mailbezorgingsprobleem op én is sowieso nodig voor de latere Facturatie/Notification Engine (facturen e-mailen naar klanten). Zie `docs/architecture.md` sectie 8 voor de overweging Resend vs. Google-inlog.

**Nog te bouwen in Fase 1:**
- Bedrijf aanmaken/bewerken UI (de knop "+ Nieuw bedrijf" doet nog niets)
- Afdelingen/Kostenplaatsen/Projecten
- Open Rekeningen
- Receipt Manager (handmatige invoer)
- Workflow Engine basis
- Facturatie (afhankelijk van Resend-koppeling voor het mailen)
- Dashboard met cijfers

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
