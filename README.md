# Polder — Restaurant Business Accounting Platform (Fase 1 / MVP)

Digitale administratie voor zakelijke "op rekening"-bestellingen bij Café Restaurant Polder.
Zie `docs/architecture.md` voor de volledige architectuur (bron van waarheid, sectie 3).

## Status

**Fase 1 in opbouw:**
- ✅ Projectstructuur, database-schema, Event Bus-skeleton
- ✅ Bedrijvenbeheer: API-route + eerste UI (lijst)
- ⏳ Nog te bouwen: bedrijf aanmaken/bewerken UI, Afdelingen/Kostenplaatsen/Projecten,
  Open Rekeningen, Receipt Manager (handmatig), Workflow Engine basis, Facturatie,
  Notification Engine, Dashboard, Auth-flow (login/registratie)

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
