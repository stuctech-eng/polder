# Polder — Security Hardening Plan

**Status: PLAN — niets uitgevoerd.** Geen migratie, geen policy-, privilege- of codewijziging, geen
deployment. Elke implementatiestap hieronder vereist een eigen, expliciete GO van Dick. Na elke stap:
testen → stoppen → her-auditen → nieuwe GO.

Datum: 2026-10-08 · Basis: Fase-0-audit (architecture.md sectie 13), baseline-migratie 0014,
volledige inventarisatie van alle routes, server-flows en schrijfacties in de codebase.

---

## 0. Samenvatting in één blik

**Kernprobleem.** De database controleert alleen *"hoort deze rij bij jouw restaurant?"*, nooit
*"mag jouw rol dit?"* of *"mag deze statusovergang?"*. De app doet dat wel, maar wie rechtstreeks met
Supabase praat omzeilt de app.

**Kernoplossing in drie lagen** (defense in depth, in deze volgorde van sterkte):
1. **Rechten per rol in RLS** — via `SECURITY DEFINER`-hulpfuncties (`my_role()`, `has_perm()`),
   één policy per tabel *per bewerking*.
2. **Triggers voor onveranderlijkheid en statusovergangen** — vergrendelde bonnen, betaalde
   facturen, logboeken en gefactureerde rekeningen zijn voor *iedereen* onveranderlijk,
   ook bij een fout in de app.
3. **Server-only schrijfflows (service-role) voor wat nooit via de gebruikersverbinding mag** —
   gebruikersprofielen en (optioneel later) logboeken. Daar moet de server het restaurant zelf
   afdwingen, want service-role omzeilt RLS.

**Wat ik NIET doe:** geen algemene RLS-bypass voor platformbeheer, geen INSERT-policy op `users`,
geen UI-wijzigingen, `restaurant_id` blijft de primaire tenantgrens.

**Opgedeeld in 11 kleine stappen**, elk met eigen migratie + eigen rollback-script + eigen GO.

### Nieuwe bevindingen bovenop Fase 0 (gevonden tijdens deze planfase)
| # | Bevinding | Ernst |
|---|---|---|
| 11 | **Gedeactiveerde gebruikers** worden alleen door middleware/`requireRole` geweigerd. Rechtstreeks met Supabase werkt hun sessie nog steeds volledig. | Hoog |
| 12 | `approval_settings.pin_hash` + `pin_salt` zijn voor **elke rol** leesbaar. Een 4–6-cijferige PIN is met een gelekte hash + salt in seconden te kraken. Pas relevant zodra directe schrijfrechten dicht zijn (H4), maar dan wel dwingend. | Middel-hoog |
| 13 | `users` SELECT: elke rol (ook bediening/keuken) kan alle teamleden met rol en actief-status lezen. App toont dit alleen aan de eigenaar. | Laag |
| 14 | `open_tabs` kan verwijzen naar een afdeling/kostenplaats/project van een *ander bedrijf* (binnen hetzelfde restaurant): geen enkele constraint. | Laag-middel |
| 15 | De goedkeurings-QR/link (`approvals.verification_code`) is bewust zichtbaar voor wie bonnen beheert (de bediening toont de QR aan de klant). Daardoor kan ook bediening de link zelf openen en "als klant" goedkeuren. Dit is inherent aan externe goedkeuring en geen database-bug — zie besluit D5. | Ontwerpkeuze |

---

## 1. Ontwerpprincipes

1. **Fail closed.** Geen rol/geen actief profiel → geen toegang.
2. **Eén policy per tabel per bewerking** (`select / insert / update / delete`), nooit meer `for all`.
3. **Rolmatrix gespiegeld in de database, met bewaking tegen verschil.** De TypeScript-matrix
   (`role-helpers.ts`) blijft de bron; `role_has_permission()` in SQL is een exacte kopie. Een
   testscript vergelijkt beide en faalt bij verschil. (Later: matrix configureerbaar maken — roadmap.)
4. **Triggers zijn de laatste verdedigingslijn** voor boekhoudkundige onveranderlijkheid; ze
   gelden ook voor `service_role`, behalve waar uitdrukkelijk toegestaan (publieke goedkeuring).
5. **Service-role alleen server-side, altijd na `requireRole`, en met expliciete tenantcontrole**
   (`target.restaurant_id === ctx.restaurantId`) — want service-role heeft geen RLS.
6. **Geen datamodel-uitbreiding die niet nodig is** (geen nieuwe tabellen in deze fase, behalve
   waar uitdrukkelijk benoemd).
7. **Elke stap is terug te draaien** (§ 15) en vooraf getest op een lege testdatabase + staging.

---

## 2. Hulpfuncties (basis voor alles) — onderdeel H1 + H9

### Probleem
`my_restaurant_id()` is `SECURITY DEFINER` zonder vast `search_path`, houdt geen rekening met
`is_active`, en er is geen rolfunctie.

### Huidige regel (productie)
```sql
create or replace function my_restaurant_id() returns uuid
language sql security definer stable
as $$ select restaurant_id from users where id = auth.uid() $$;   -- proconfig = null
```

### Nieuwe regel
```sql
create or replace function public.my_restaurant_id() returns uuid
language sql stable security definer set search_path = public, pg_temp
as $$ select restaurant_id from public.users where id = auth.uid() and is_active $$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public, pg_temp
as $$ select role from public.users where id = auth.uid() and is_active $$;

-- exacte kopie van PERMISSIONS in lib/user-management/role-helpers.ts
create or replace function public.role_has_permission(p_role text, p_perm text) returns boolean
language sql immutable set search_path = public, pg_temp
as $$ select case p_perm
  when 'VIEW_DASHBOARD'        then p_role in ('owner','manager','administratie')
  when 'VIEW_REVENUE'          then p_role in ('owner','manager','administratie')
  when 'MANAGE_COMPANIES'      then p_role in ('owner','administratie')
  when 'MANAGE_OPEN_TABS'      then p_role in ('owner','manager','administratie','bediening')
  when 'MANAGE_RECEIPTS'       then p_role in ('owner','manager','administratie','bediening')
  when 'APPROVE_RECEIPTS'      then p_role in ('owner','manager')
  when 'MANAGE_INVOICES'       then p_role in ('owner','administratie')
  when 'VIEW_DAILY_CLOSING'    then p_role in ('owner','manager','administratie')
  when 'EXECUTE_DAILY_CLOSING' then p_role in ('owner','manager')
  when 'MANAGE_TEAM'           then p_role in ('owner')
  when 'MANAGE_SETTINGS'       then p_role in ('owner','administratie')
  else false end $$;

create or replace function public.has_perm(p_perm text) returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$ select public.role_has_permission(public.my_role(), p_perm) $$;

revoke execute on function public.my_restaurant_id(), public.my_role(), public.has_perm(text)
  from public, anon;
grant  execute on function public.my_restaurant_id(), public.my_role(), public.has_perm(text)
  to authenticated, service_role;
```

### Huidig → gewenst gedrag
Nu: gedeactiveerde gebruiker kan via de API nog alles binnen het restaurant. Straks: `my_restaurant_id()`
en `my_role()` geven `NULL` → elke policy die ze gebruikt faalt dicht.

### Betrokken code
Geen codewijziging. De bestaande `users`-policy "own profile" (`id = auth.uid()`) blijft zodat
middleware nog kan lezen dat iemand gedeactiveerd is (`lib/supabase/middleware.ts`).

### Gevolgen voor bestaande functionaliteit
- Bestaande policies die `my_restaurant_id()` al gebruiken (`daily_closings`, `users`) blijven werken.
- Een gedeactiveerde gebruiker verliest ook databasetoegang (gewenst).
- `create or replace` met identieke signatuur: geen drop nodig.

### Testgevallen / security-tests
- Actief + inactief profiel: `select my_role(), my_restaurant_id()` → waarde resp. `NULL`.
- `select proconfig from pg_proc where proname in ('my_restaurant_id','my_role','has_perm')` bevat `search_path`.
- `anon` kan de functies niet uitvoeren (`has_function_privilege('anon', ..., 'execute')` = false).
- Consistentietest: elke (rol × permissie) uit `PERMISSIONS` (TS) geeft hetzelfde als `role_has_permission()`.

### Migratievolgorde / rollback
Stap 1 (eerste, additief). Rollback: `create or replace` terug naar de vorige definitie (staat in
`supabase/rollbacks/0015_rollback.sql`); nieuwe functies droppen.

---

## 3. Onderdeel H2 — `users`

### A. Probleem
Bevindingen 1, 2, 13 en het open uitnodigingsprobleem (§13.4 van het Fase-0-rapport).

### B/C. Huidige policies en gedrag
```
users SELECT  "users can see own profile"           id = auth.uid()
users SELECT  "users can see team members"          restaurant_id = my_restaurant_id()
users UPDATE  "team managers can update team members"  restaurant_id = my_restaurant_id()  (check: idem)
users DELETE  "team managers can delete team members"  restaurant_id = my_restaurant_id()
users INSERT  — geen policy
grants: authenticated heeft SELECT, INSERT, UPDATE, DELETE
```
Gevolg: elke teamgenoot kan via directe API elke collega (ook zichzelf) naar `owner` zetten of
verwijderen. De uitnodiging schrijft het profiel via de gebruikersverbinding en kan dus falen.

### D. Gewenst gedrag
- Lezen: eigen profiel altijd; andere teamleden alleen met `MANAGE_TEAM` (besluit D2).
- Aanmaken/wijzigen/verwijderen van profielen: **uitsluitend server-side** via service-role, na
  `requireRole("MANAGE_TEAM")` en met expliciete regels (hieronder).
- DB-garantie: er blijft altijd minstens één actieve `owner` per restaurant.

### E → F. Oude → nieuwe regel
```sql
-- policies
drop policy "team managers can update team members" on users;
drop policy "team managers can delete team members" on users;
drop policy "users can see team members" on users;
create policy "users read team (owner only)" on users
  for select using (restaurant_id = my_restaurant_id() and has_perm('MANAGE_TEAM'));
-- "users can see own profile" blijft (id = auth.uid())

-- privileges
revoke insert, update, delete on users from authenticated;     -- alleen SELECT blijft

-- DB-vangnet (ook voor service-role): id en restaurant_id onveranderlijk
create function users_guard() returns trigger ... -- BEFORE UPDATE: raise als new.id <> old.id
                                                  --               of new.restaurant_id <> old.restaurant_id
-- DB-vangnet: laatste actieve owner (constraint-trigger, deferrable)
create constraint trigger users_keep_owner after update or delete on users
  deferrable initially deferred for each row execute function users_keep_owner();
-- users_keep_owner: bij UPDATE/DELETE van een actieve owner → er moet nog ≥1 actieve owner in
-- hetzelfde restaurant bestaan, tenzij het restaurant zelf is verwijderd (cascade).
```

### G. Betrokken code (server-side wijzigingen)
- `lib/user-management/team-service.ts`, `user-repository.ts`: schrijfbewerkingen via
  `createSupabaseAdminClient()` i.p.v. de gebruikersverbinding.
- `lib/user-management/invitation-service.ts`: bij mislukte profiel-insert het zojuist aangemaakte
  Auth-account weer verwijderen (`admin.auth.admin.deleteUser`) → geen wezen meer. Duidelijke foutmelding
  als het e-mailadres al bestaat.
- `app/api/team/route.ts`, `app/api/team/[id]/route.ts`: ongewijzigde contracten, wel:
  - `ctx.restaurantId === target.restaurant_id` expliciet controleren (service-role heeft geen RLS);
  - rol alleen uit toegestane waarden; niet jezelf degraderen/deactiveren/verwijderen als je de enige owner bent;
  - rolwijziging en deactivering altijd in `activity_log` + `domain_events` (bestaat al).
- Opruimen: het wezen-account `stuctech@gmail.com` (besluit D4).

### H. Gevolgen
Teampagina (`team/page.tsx`) leest met `MANAGE_TEAM` → blijft werken. Niemand anders ziet het team meer.
Uitnodigen en rolwijzigen werken via de server; gedrag voor de gebruiker ongewijzigd.

### I/J. Testgevallen (directe Supabase-aanroepen met JWT per rol)
- bediening: `PATCH /users?id=eq.<eigen id> {role:'owner'}` → **geweigerd** (geen UPDATE-recht).
- manager: `DELETE /users?id=eq.<owner>` → geweigerd; `POST /users` → geweigerd.
- bediening: `GET /users` → alleen eigen rij.
- owner via app: rol wijzigen, deactiveren, verwijderen, uitnodigen → werkt; laatste owner verwijderen → geweigerd (app én DB-trigger).
- Gebruiker restaurant A probeert via app `/api/team/<id van B>` → geweigerd (tenantcontrole).
- Service-role probeert `restaurant_id` van een user te wijzigen → trigger weigert.
- Uitnodiging waarbij profiel-insert faalt (simuleren) → geen wees in `auth.users`.

### K/L. Volgorde / rollback
Stap 3 (na helpers en restaurants). Code en migratie samen in één release: migratie eerst op staging,
dan code, dan productie. Rollback: policies/grants terugzetten (rollback-script), vorige code-tag terug.

---

## 4. Onderdeel H3 — `restaurants`

### A. Probleem
Bevinding 3: een gewone gebruiker kan zijn restaurant wijzigen of verwijderen; verwijderen cascadeert
naar alle data.

### B/C. Nu
Policy `tenant isolation restaurants` = `for all using (id in (select restaurant_id from users where id = auth.uid()))`;
grants: SELECT/INSERT/UPDATE/DELETE voor `authenticated`.
De codebase **schrijft nergens** naar `restaurants` (gecontroleerd): geen impact op de app.

### D/E/F. Gewenst / oud / nieuw
```sql
drop policy "tenant isolation restaurants" on restaurants;
create policy "restaurants read own" on restaurants
  for select using (id = my_restaurant_id());
revoke insert, update, delete on restaurants from authenticated;
```
Cascade-delete: na deze stap kan *alleen* service-role/databasebeheerder een restaurant verwijderen.
Later (platformbeheer): **nooit hard verwijderen via de app**; alleen `status = inactive`. Hard delete = aparte,
gelogde procedure (privacyfase: dataverwijdering).

### G/H. Code / gevolgen
Geen codewijziging; restaurantnaam bewerken bestaat nog niet (komt via server bij restaurantbeheer).

### I/J. Tests
- bediening/owner: `PATCH /restaurants?id=eq.<eigen> {name:'x'}` → geweigerd; `DELETE` → geweigerd.
- Restaurant A leest restaurant B → 0 rijen.
- App: alle schermen laden (restaurantnaam wordt nergens geschreven).

### K/L. Volgorde / rollback
Stap 2. Rollback: oude policy + grants terug.

---

## 5. Onderdeel H4 — boekhoudkundige en statusgevoelige data

### A. Probleem
Bevinding 4 (deels) en 5: vergrendelen, goedkeuren, factuurstatussen, betalingen en dagafsluiting worden
alleen in de app afgedwongen.

### Aanpak (per tabel/actie: wat DB, wat server)
| Wat | Database (RLS + trigger) | Server (blijft) |
|---|---|---|
| Wie mag lezen/schrijven | RLS per rol (`has_perm`) | `requireRole` (blijft, defense in depth) |
| Statusovergang geldig? | **Trigger** (harde regels, zie onder) | Foutmeldingen, extra validaties |
| Onveranderlijk na vergrendelen/betaald/gefactureerd | **Trigger** | idem |
| Bedrijfsregels (verplichte velden, PIN, goedkeuringsmethode) | — | **Server** (te variabel voor SQL) |
| Wie mag goedkeuren | RLS/trigger (`APPROVE_RECEIPTS`) | server (PIN/e-mail/QR-verificatie) |

De publieke goedkeuring (`/api/public-approve`) gebruikt service-role en blijft toegestaan voor precies
twee overgangen (zie trigger-uitzondering).

### Opgedeeld in vier deelstappen met eigen GO: H4a, H4b, H4c, H4d

#### H4a — `open_tabs`, `receipts`, `receipt_lines`, `approvals`

**Huidig**: `for all`, restaurant-only.

**Nieuw (policies)**
```
open_tabs     select  has_perm('MANAGE_OPEN_TABS') and restaurant_id = my_restaurant_id()
              insert  has_perm('MANAGE_OPEN_TABS') and restaurant_id = my_restaurant_id() and status = 'open'
              update  has_perm('MANAGE_OPEN_TABS') and restaurant_id = my_restaurant_id()
              delete  has_perm('MANAGE_OPEN_TABS') and restaurant_id = my_restaurant_id()
receipts      select/insert/update/delete  idem met has_perm('MANAGE_RECEIPTS')   (insert alleen status draft|linked)
receipt_lines select/insert/update/delete  via receipt_id → ouder-bon (zelfde restaurant) + has_perm('MANAGE_RECEIPTS')
approvals     select  has_perm('MANAGE_RECEIPTS') via company/restaurant
              insert  has_perm('MANAGE_RECEIPTS'), status = 'pending'
              update  has_perm('APPROVE_RECEIPTS')                (service-role voor publieke link)
              delete  — geen policy
```
**Nieuw (triggers)**
- `receipts_guard` (BEFORE INSERT/UPDATE/DELETE):
  - toegestane overgangen: `draft|linked → pending_approval` (MANAGE_RECEIPTS);
    `pending_approval → approved|locked` (**alleen** `APPROVE_RECEIPTS` of service-role);
    `pending_approval → linked` (afwijzing; `APPROVE_RECEIPTS` of service-role);
    `approved → locked` (`APPROVE_RECEIPTS`);
  - `approved`/`locked`: **geen enkele veldwijziging, geen delete** (ook niet door service-role, behalve de
    twee statusovergangen hierboven);
  - velden `receipt_number/date/notes/total` alleen wijzigbaar in `draft|linked`;
  - delete alleen in `draft|linked` en alleen als de rekening niet `invoiced` is.
- `receipt_lines_guard`: alleen schrijven zolang de ouder-bon `draft|linked` is.
- `open_tabs_guard`: `open → closed` (MANAGE_OPEN_TABS); `closed → invoiced` alleen met
  `MANAGE_INVOICES`; nooit terug; `invoiced` onveranderlijk; delete alleen `status = 'open'` zonder bonnen.
- `approvals_guard`: `pending → approved|rejected|expired` eenmalig; daarna onveranderlijk;
  `verification_code`, `receipt_id`, `company_id`, `method`, `requested_at` onveranderlijk.

**Betrokken routes**: `open-tabs/*`, `receipts/*`, `receipts/[id]/approve`, `receipts/[id]/request-approval`,
`public-approve/[token]`. **Geen codewijziging** verwacht: de app voert exact deze overgangen al uit; de
trigger legt vast wat al de bedoeling was. (Bevestigen in staging per route.)

**Gevolgen / risico's**: te strenge trigger kan een bestaande flow breken, bijv. `approve` met `autoLock=false`
(status `approved`) of een bon die opnieuw wordt ingediend na afwijzing. Mitigatie: per overgang een
testcase (§ 13) en bestaande data vooraf controleren.

**Tests (direct API)**: bediening zet bon op `locked` → geweigerd; bediening past `total` aan op `locked`
bon → geweigerd; bediening zet `pending_approval → approved` → geweigerd; manager doet dat wel → toegestaan;
iedereen verwijdert vergrendelde bon → geweigerd; insert bon met `status='locked'` → geweigerd;
tab `invoiced` weer `open` → geweigerd; manager zet `closed → invoiced` → geweigerd.

#### H4b — `invoices`, `invoice_lines`, `payments`, `documents`
```
invoices       select  has_perm('VIEW_REVENUE')      (owner, manager, administratie)
               insert  has_perm('MANAGE_INVOICES') and status = 'draft'
               update  has_perm('MANAGE_INVOICES')
               delete  — geen policy (boekhoudkundig onveranderlijk)
invoice_lines  select  idem VIEW_REVENUE;  insert  MANAGE_INVOICES alleen terwijl factuur 'draft';  update/delete — geen
payments       select  VIEW_REVENUE;  insert  MANAGE_INVOICES;  update/delete — geen  (correctie = nieuwe betaling)
documents      select  MANAGE_INVOICES;  insert  MANAGE_INVOICES;  update/delete — geen
```
Triggers: `invoices_guard`: toegestaan `draft → sent`, `sent → paid|overdue`, `overdue → paid`, `sent → overdue`
(app laat nu ook `draft → paid/overdue` toe via het PATCH-schema — **te bevestigen**, zie D6); `paid` is
terminaal; bedrag/nummer/bedrijf onveranderlijk na `draft`. `payments_guard`: bedrag > 0, factuur in
zelfde restaurant, factuur niet `draft`.
Code: `app/api/invoices/*`, `open-tabs/[id]/generate-invoice` (maakt factuur + regels + document + zet tab op
`invoiced`: blijft kloppen met de regels hierboven).

#### H4c — `daily_closings`
```
select  has_perm('VIEW_DAILY_CLOSING');  insert  has_perm('EXECUTE_DAILY_CLOSING');  update/delete — geen
```
Heropenen van een dag (roadmap) krijgt later een eigen, gelogde server-flow; de kolommen `reopened_*` bestaan al.

#### H4d — stamgegevens en instellingen
```
companies, contacts, departments, cost_centers, projects, company_codes
   select  rollen met MANAGE_OPEN_TABS of MANAGE_COMPANIES (owner, manager, administratie, bediening)
   insert/update  has_perm('MANAGE_COMPANIES');  delete — geen (geen route; cascade via bedrijf)
configurations, workflow_rules
   select  zoals boven;  insert/update  has_perm('MANAGE_SETTINGS');  delete — geen
approval_settings  → zie H10
notifications      → select VIEW_REVENUE; schrijven alleen service-role (nu ongebruikt)
integration_plugins → select/insert/update/delete alleen MANAGE_SETTINGS en voorlopig geen enkele schrijfroute;
                      secrets komen NIET hier (zie H11 / integratiefase)
```

### K/L (H4 algemeen)
Volgorde: H4a → H4b → H4c → H4d, elke deelstap eigen GO. Rollback per deelstap: oude `for all`-policies en
grants uit het rollback-script, triggers droppen.

---

## 6. Onderdeel H5 — logboeken (`audit_log`, `activity_log`, `domain_events`)

### A/B/C. Probleem en nu
Bevinding 4: `for all` → elke teamgenoot kan logregels wijzigen en wissen of valse regels toevoegen.
Schrijfplekken: 20+ routes via de gebruikersverbinding (`activity_log`, `domain_events`); `audit_log` wordt nu
in de code niet geschreven.

### D. Gewenst
Append-only. Gewone gebruikers kunnen lezen (alleen de rollen die dat nodig hebben) en toevoegen voor het
eigen restaurant en onder eigen naam; nooit wijzigen of wissen.

### E → F
```sql
drop policy "tenant isolation activity_log" on activity_log;        -- idem audit_log, domain_events
create policy "activity_log read"   on activity_log for select using (restaurant_id = my_restaurant_id() and has_perm('VIEW_DASHBOARD'));
create policy "activity_log insert" on activity_log for insert with check
  (restaurant_id = my_restaurant_id() and user_id = auth.uid());
-- domain_events: with check (restaurant_id = my_restaurant_id() and published_by = auth.uid())
-- audit_log:     with check (restaurant_id = my_restaurant_id() and changed_by = auth.uid())
revoke update, delete, truncate on activity_log, audit_log, domain_events from authenticated, anon;
create function log_append_only() returns trigger ...   -- BEFORE UPDATE OR DELETE: raise exception,
-- behalve wanneer het restaurant zelf is verwijderd (cascade); geldt ook voor service_role
```

### G. Code
**H5a (append-only)**: geen codewijziging. Het `with check` vereist `user_id/published_by = auth.uid()`:
controleren dat alle bestaande inserts dat al doen (`ctx.userId`); de publieke goedkeuring gebruikt
service-role en valt erbuiten.
**H5b (optioneel, later; besluit D3)**: alle logregels via één server-helper `writeLog()` met
service-role en `INSERT` volledig intrekken voor `authenticated` → logregels zijn dan ook niet meer te
vervalsen (authenticiteit, niet alleen onveranderlijkheid). ~20 aanroepplaatsen.

### H. Gevolgen
Oude logregels blijven; nieuwe kunnen niet gewijzigd worden. Retentie/verwijdering (AVG) later via een
gecontroleerde server-functie, niet via de gebruikersverbinding.

### I/J. Tests
`PATCH/DELETE /activity_log` als owner → geweigerd; `TRUNCATE` niet beschikbaar; insert met andere
`user_id` → geweigerd; insert voor restaurant B → geweigerd; normale app-acties schrijven nog logregels.

### K/L. Volgorde / rollback
Stap 4. Rollback: oude policy + grants + trigger droppen.

---

## 7. Onderdeel H6 — Storage (`documents`-bucket)

### A/B/C. Nu
Policies: SELECT, INSERT, UPDATE per restaurant-map (`foldername[1]::uuid in (…)`); geen DELETE. Elke teamgenoot
kan factuur-PDF's van het eigen restaurant lezen én overschrijven. De cast `::uuid` geeft een foutmelding bij een
pad dat niet met een uuid begint.

### D/E/F. Gewenst / nieuw
```sql
drop policy "tenant isolation documents bucket read"   on storage.objects;
drop policy "tenant isolation documents bucket update" on storage.objects;
drop policy "tenant isolation documents bucket upload" on storage.objects;
create policy "documents read"   on storage.objects for select using
  (bucket_id = 'documents' and (storage.foldername(name))[1] = my_restaurant_id()::text and has_perm('MANAGE_INVOICES'));
create policy "documents upload" on storage.objects for insert with check
  (bucket_id = 'documents' and (storage.foldername(name))[1] = my_restaurant_id()::text and has_perm('MANAGE_INVOICES'));
-- geen UPDATE- en geen DELETE-policy → bestanden zijn onveranderlijk
```

### G. Code
`app/api/open-tabs/[id]/generate-invoice/route.ts`: `upload(..., { upsert: true })` → `upsert: false`
(het pad bevat de nieuwe factuur-id, dus er is nooit een bestaand bestand; `upsert` vereist anders UPDATE-recht).
`invoices/[id]/pdf-url` blijft (signed URL, `MANAGE_INVOICES`).

### H. Gevolgen
Manager kan geen factuur-PDF meer openen via storage (heeft ook geen `MANAGE_INVOICES`; de route staat dit nu al niet toe).

### I/J. Tests
Administratie uploadt PDF in eigen map → ok; overschrijft bestaand → geweigerd; bediening leest → geweigerd;
upload in map van restaurant B → geweigerd; pad zonder uuid → net geweigerd i.p.v. fout.

### K/L. Volgorde / rollback
Stap 6. Rollback: oude drie policies terug.

---

## 8. Onderdeel H7 — cross-restaurant (en cross-bedrijf) referenties

### A/B/C. Probleem en nu
Bevinding 8 en 14. Foreign keys controleren alleen of de rij *bestaat*, niet van wie die is (FK's negeren RLS).
RLS-checks zitten op de kind-rij zelf, niet op de verwezen ouder. De routes controleren dit in de app (les v1.20),
de database niet.

### D. Gewenst
Een kindrij kan niet naar een ouder in een ander restaurant verwijzen, en binnen een restaurant moeten
afdeling/kostenplaats/project bij hetzelfde bedrijf horen als de rekening.

### E → F: triggers, geen schema-uitbreiding
Eén generieke functie `assert_same_restaurant(child_restaurant, parent_table, parent_id)` + per relatie een
`BEFORE INSERT OR UPDATE`-trigger. Relaties:
`open_tabs → companies, departments, cost_centers, projects, contacts` (+ afdeling/kostenplaats/project/contact
horen bij `open_tabs.company_id`); `receipts → open_tabs`; `invoices → companies`; `invoice_lines → invoices, receipts`;
`approvals → receipts, companies`; `approval_settings/company_codes/configurations/workflow_rules → companies`;
`departments/cost_centers/projects/contacts → companies` (via bedrijf); `payments → invoices`;
gebruikersverwijzingen (`created_by`, `closed_by`, `reopened_by`, `published_by`, `changed_by`, `user_id`,
`recipient_user_id`) → `users` in hetzelfde restaurant.
Waarom triggers en geen samengestelde FK's: alle kindtabellen zonder eigen `restaurant_id` (afdeling, project, …)
zouden een extra kolom + backfill nodig hebben; triggers vangen ook service-role fouten af.

### G/H. Code en gevolgen
Geen codewijziging. Eerst een **alleen-lezen controlequery** op bestaande data (zijn er al afwijkende rijen?),
anders blokkeert de trigger legitiem bestaande data bij de eerstvolgende wijziging.

### I/J. Tests
Insert `open_tabs` in A met `company_id` uit B → geweigerd; met afdeling van ander bedrijf → geweigerd;
`approvals` met bon uit B → geweigerd; normale flows ongewijzigd.

### K/L. Volgorde / rollback
Stap 5. Rollback: triggers droppen.

---

## 9. Onderdeel H8 — overbodige databaseprivileges

### A/B/C. Nu (productie, gemeten)
`anon`: REFERENCES, TRIGGER, TRUNCATE op alle 25 tabellen. `authenticated`: alles incl. TRUNCATE/TRIGGER/REFERENCES.
`service_role`: alles. (PostgREST biedt geen TRUNCATE aan; het is dus alleen een risico bij directe SQL-toegang —
maar onnodig breed.)

### D/E/F. Gewenst / nieuw
```sql
revoke truncate, trigger, references on all tables in schema public from anon, authenticated, service_role;
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
alter default privileges in schema public revoke truncate, trigger, references on tables from anon, authenticated, service_role;
```
Daarna **least privilege per tabel** voor `authenticated` (welke bewerkingen bestaan voor wie), als afsluitende
stap (zie rollenmatrix §14): bijv. alleen SELECT op `restaurants`/`users`, geen DELETE op boekhoudtabellen.

### G/H. Code en gevolgen
Geen. Migraties draaien als eigenaar (`postgres`) en zijn niet afhankelijk van deze rechten.

### I/J. Tests
`select has_table_privilege('authenticated','public.receipts','truncate')` = false (alle tabellen);
catalogus-lint: geen tabel waarop `anon` iets mag; app volledig doorlopen.

### K/L. Volgorde / rollback
Stap 2b (direct na `restaurants`, laag risico) + afsluitende trimming als stap 11. Rollback: `grant` terug.

---

## 10. Onderdeel H10 — geheimen in `approval_settings` (nieuw)

### A/B/C. Probleem
Bevinding 12. `pin_hash` en `pin_salt` zijn voor elke teamgenoot leesbaar; `getApprovalSettings()` leest ze met de
gebruikersverbinding (`lib/approval/approval-service.ts`).

### D/E/F. Gewenst / nieuw
```sql
revoke select (pin_hash, pin_salt) on approval_settings from authenticated;   -- kolomrechten; ná tabel-SELECT trimmen
-- schrijven blijft via de server (route valideert MANAGE_SETTINGS en schrijft de hash)
```

### G. Code
- `lib/approval/approval-service.ts` `getApprovalSettings`: PIN-velden alleen ophalen via service-role, alleen
  aangeroepen vanuit `receipts/[id]/approve` (na `requireRole("APPROVE_RECEIPTS")`) en
  `lib/approval/providers/*`. Overige aanroepen halen alleen niet-geheime velden (user client).
- `app/api/companies/[id]/approval-settings/route.ts`: "bestaat er een PIN?" afleiden zonder de hash te lezen.

### H/I/J. Gevolgen / tests
Directe `select pin_hash` als bediening → permission denied; PIN-goedkeuring via de app werkt; PIN wijzigen
(administratie/owner) werkt. Mogelijk later: PIN-pogingen beperken (rate limit) — roadmap.

### K/L. Volgorde / rollback
Stap 10, ná H4a. Rollback: kolomrecht terug + vorige code.

---

## 11. Besluiten en bewust open punten

- **D1 — keuken**: heeft in de huidige matrix geen enkele permissie. Voorstel: **geen leestoegang tot bedrijfs-
  en boekhouddata** in de database (alleen eigen profiel). Zodra keuken functies krijgt, wordt de matrix
  uitgebreid.
- **D2 — `users` lezen**: alleen eigenaar ziet het team (voorstel), de rest alleen het eigen profiel.
- **D3 — logauthenticiteit (H5b)**: nu meenemen of later? Voorstel: H5a nu, H5b vóór het eerste echte restaurant.
- **D4 — wezenaccount `stuctech@gmail.com`**: verwijderen (voorstel) of koppelen aan een restaurant.
- **D5 — goedkeuringslink**: bediening kan de eigen QR/link zelf "als klant" goedkeuren. Voorstel: accepteren voor
  nu (niet te scheiden van de klant), en in de roadmap-verfijningen toevoegen: verloop, intrekken,
  "aanmaker ≠ goedkeurder" bij interne goedkeuring, rate limit.
- **D6 — factuurstatus**: de app laat `draft → paid/overdue` nu technisch toe. Voorstel DB-regels:
  `draft → sent`, `sent → paid | overdue`, `overdue → paid`; `draft → paid` blokkeren? (functionele keuze Dick/klant.)
- **D7 — staging**: tweede (gratis) Supabase-project "polder-staging" aanmaken om elke stap eerst op echte
  PostgREST/Auth te testen. Sterk aanbevolen.
- **D8 — onveranderlijkheid**: facturen, betalingen, documenten en logs krijgen geen DELETE; correcties zijn nieuwe
  regels (creditnota's/correctieboekingen komen in een latere fase).

---

## 12. Rollenmatrix (databaseniveau, voorstel)

Legenda: **L** lezen · **A** aanmaken · **W** wijzigen · **V** verwijderen · **S** status wijzigen · — niet toegestaan.
"(srv)" = alleen via de server (service-role), nooit rechtstreeks. Basis: bestaande `PERMISSIONS` in
`role-helpers.ts`, vergeleken met de daadwerkelijke `requireRole`-aanroepen per route: **de matrix klopt met de
code**; bevindingen daaruit staan in de voetnoten.

| Resource | Owner | Manager | Administratie | Bediening | Keuken |
|---|---|---|---|---|---|
| Stamgegevens (bedrijven, contacten, afdelingen, kostenplaatsen, projecten, codes) | L A W | L | L A W | L | — |
| Instellingen (configuraties, workflowregels, goedkeuringsinstellingen) | L A W | L¹ | L A W | L² | — |
| Open rekeningen | L A W V³ S⁴ | L A W V³ S⁴ | L A W V³ S⁴ | L A W V³ S⁴ | — |
| Bonnen + regels (draft/linked) | L A W V | L A W V | L A W V | L A W V | — |
| Bon indienen voor goedkeuring (→ pending) | S | S | S | S | — |
| Bon goedkeuren / afwijzen (intern) | S | S | — | — | — |
| Bon vergrendeld/goedgekeurd | L (onveranderlijk) | L | L | L | — |
| Goedkeuringen (`approvals`) | L | L | L | L | — |
| Facturen + regels | L A S | L | L A S | — | — |
| Betalingen | L A | L | L A | — | — |
| Factuur-PDF's (storage) | L A | — | L A | — | — |
| Dagafsluiting | L A | L A | L | — | — |
| Logboeken | L (A via app) | L | L | — | — |
| Gebruikersbeheer (`users`) | L, A/W/V (srv) | eigen profiel | eigen profiel | eigen profiel | eigen profiel |
| Restaurantgegevens | L | L | L | L | L |
| Restaurantbeheer (wijzigen/verwijderen/aanmaken) | — (platform, later) | — | — | — | — |

¹ Manager leest instellingen niet via een eigen scherm, maar het goedkeuringsproces vraagt de methode op. 
² Bediening leest verplichte velden/workflow nodig voor bonnen invoeren; géén PIN-hash (H10).
³ Verwijderen alleen zolang de rekening `open` is en geen bonnen heeft.
⁴ `open → closed` voor MANAGE_OPEN_TABS; `closed → invoiced` alleen via factuurgeneratie (MANAGE_INVOICES).

**Bevindingen uit de matrixcontrole** (geen fouten, wel aandachtspunten):
- Keuken heeft geen permissie → in de database geen toegang (D1).
- Manager heeft VIEW_REVENUE maar geen MANAGE_INVOICES: mag facturen lezen, niet wijzigen — klopt met dashboard/dagafsluiting.
- `generate-invoice` vereist MANAGE_INVOICES (owner, administratie); een manager kan dus een rekening sluiten maar niet factureren.
- De `approve`-route vereist APPROVE_RECEIPTS (owner, manager); administratie kan indienen maar niet goedkeuren.
- Alle routes gebruiken één permissie per actie; nergens rolnamen. De `PERMISSIONS`-comment in `role-helpers.ts` klopt met de arrays.

---

## 13. Teststrategie

### 13.1 Drie testlagen
1. **Lokale Postgres** (zoals bij Fase 0, met nagebootste `auth`/`storage`): migratieketen vanaf leeg + productie-simulatie;
   SQL-testbestanden in `supabase/tests/hardening/` die per rol `set role authenticated` + `request.jwt.claim.sub`
   zetten en elke verwachte toestaan/weigeren verifiëren. Draait in seconden, volledig herhaalbaar.
2. **Staging-Supabase** (D7): echte PostgREST/Auth. Node-testscript met `supabase-js`: 2 restaurants × 5 rollen
   (+ 1 gedeactiveerde gebruiker), echte inlogtokens, directe REST-aanroepen.
3. **App-regressie**: `tsc`, `build`, en een handmatige flow per rol: bon invoeren → indienen → goedkeuren (PIN,
   bevestigen, e-mail, QR) → rekening sluiten → factureren → betaling → dagafsluiting → team beheren.

### 13.2 Bewijs "restaurant A kan B niet raken"
- **Matrixtest**: voor élke tabel × bewerking (select/insert/update/delete) probeert een owner van A rijen van B te
  lezen/wijzigen/verwijderen/aan te maken → verwacht 0 rijen of fout. Wordt automatisch uit `pg_tables` gegenereerd,
  zodat een nieuwe tabel zonder test opvalt.
- **Catalogus-lint** (read-only queries, ook voor productie): (a) RLS aan op elke tabel; (b) geen policy met
  `true`/zonder restaurantvoorwaarde; (c) elke policy gebruikt `my_restaurant_id()` of een gelijkwaardige
  ouder-keten; (d) geen `for all`; (e) geen TRUNCATE/TRIGGER/REFERENCES voor `anon/authenticated`.
- **Cross-referentietest** (H7): inserts met ouder uit B → altijd geweigerd.

### 13.3 Bewijs "rollen kunnen niet escaleren"
Per rol (owner, manager, administratie, bediening, keuken, gedeactiveerd) via directe aanroepen:
- E1 eigen rol naar `owner` wijzigen · E2 collega/owner verwijderen · E3 profiel aanmaken ·
- E4 restaurant wijzigen/verwijderen · E5 `restaurant_id` van eigen profiel wijzigen ·
- E6 logregel wijzigen/verwijderen/vervalsen · E7 vergrendelde bon/betaalde factuur wijzigen of verwijderen ·
- E8 statusovergang zonder recht (bijv. bediening `pending → locked`) · E9 PIN-hash lezen ·
- E10 factuur-PDF overschrijven · E11 gedeactiveerde gebruiker doet iets.
Verwacht resultaat per rol staat in een tabel in het testbestand; elke afwijking is een falende test.

### 13.4 Consistentietest matrix
Script dat `PERMISSIONS` (TS) en `role_has_permission()` (SQL) voor alle rol×permissie-combinaties vergelijkt.

### 13.5 Bestaande Polder-flow niet breken
Voor elke stap: lijst van routes die de betreffende tabel schrijven (zie § 5–10 "Betrokken code") en per route
één testgeval uit de appregressie. Plus controle op bestaande data: alleen-lezen queries die rijen opsporen die de
nieuwe regels zouden schenden (bijv. bonnen in `approved` zonder `locked`, afwijkende verwijzingen).

---

## 14. Migratievolgorde (11 stappen — elke stap eigen GO)

| Stap | Inhoud | Code? | Risico |
|---|---|---|---|
| 0 | Voorwerk: staging aanmaken (D7), alleen-lezen data-checks, rollback-map + testharnas | nee | laag |
| 1 | **H1+H9**: hulpfuncties, `search_path`, `is_active` fail-closed | nee | laag-middel (inactieve gebruikers) |
| 2 | **H3** `restaurants` + **H8a** TRUNCATE/TRIGGER/REFERENCES weg | nee | laag |
| 3 | **H2** `users` + server-side team-/uitnodigflow | **ja** | middel |
| 4 | **H5a** logboeken append-only | nee | laag-middel |
| 5 | **H7** cross-referentietriggers (na datacheck) | nee | middel |
| 6 | **H6** storage | **ja** (1 regel) | laag |
| 7 | **H4a** rekeningen, bonnen, goedkeuringen | nee¹ | **hoog** |
| 8 | **H4b** facturen, betalingen, documenten | nee¹ | hoog |
| 9 | **H4c+H4d** dagafsluiting, stamgegevens, instellingen, plugins | nee | middel |
| 10 | **H10** PIN-geheimen | **ja** | middel |
| 11 | **H8b** least-privilege per tabel (afsluitende trimming) + eindaudit + herhaling van alle tests | nee | laag |

¹ Verwacht geen codewijziging; bevestigen in staging.
Optioneel later: **H5b** (logs alleen via server), na besluit D3.

Waarom deze volgorde: eerst de fundamenten en de laag-risico stappen, dan `users` (grootste privilege-escalatie),
dan logs en integriteit, dan de risicovolle statusregels als die gereedschap en testharnas al bewezen zijn, en als
laatste de trimming die alles samenvat.

---

## 15. Rollback- en herstelstrategie

1. **Per migratie een rollback-script** in `supabase/rollbacks/` (zelfde nummer), dat de vorige policies, grants,
   functies en triggers exact herstelt. Elk script wordt vóór gebruik in staging bewezen.
2. **Eén transactie per migratie** (`begin; … commit;`): faalt iets, dan verandert er niets.
3. **Eerst nieuw, dan oud weghalen**: nieuwe policies worden in dezelfde transactie aangemaakt voordat de oude
   verdwijnen, zodat er nooit een moment zonder bescherming of zonder toegang is.
4. **Staging eerst, productie daarna**; code- en databasewijzigingen die samenhangen (stap 3, 6, 10) in volgorde:
   migratie op staging → code op staging → test → migratie productie → code productie. De code is zo geschreven dat
   hij ook vóór de migratie werkt (service-role schrijft ook met de oude policies).
5. **Noodknop**: een vooraf getest script dat alle `has_perm`-policies tijdelijk vervangt door de oude
   restaurant-only policies (terugval naar Fase-0-toestand), voor het geval productie onverwacht geblokkeerd raakt.
6. **Gegevensveiligheid**: dit is nog testdata. Voor elke productiestap controleren welke back-upmogelijkheden het
   Supabase-abonnement biedt; zo niet, dan zijn rollback-scripts + staging het vangnet en de enige gegevens zijn
   testgegevens.
7. **Na elke stap**: her-audit (catalogus-lint + matrixtest) en vastleggen in `architecture.md` + README.

---

## 16. Bestanden die geraakt worden (overzicht)

- **Nieuw**: `supabase/migrations/0015…0025_*.sql`, `supabase/rollbacks/*`, `supabase/tests/hardening/*`,
  testscript voor staging.
- **Wijzigen (code)**: `lib/user-management/{team-service,user-repository,invitation-service}.ts`,
  `app/api/team/route.ts`, `app/api/team/[id]/route.ts`, `app/api/open-tabs/[id]/generate-invoice/route.ts` (upsert),
  `lib/approval/approval-service.ts`, `app/api/companies/[id]/approval-settings/route.ts`.
- **Niet geraakt**: UI, navigatie, Daily Closing-logica, Resend/e-mail, keep-alive, publieke goedkeuringsroute
  (blijft service-role; de trigger staat haar twee overgangen toe).

## 17. Wat bewust NIET in deze hardening zit
Platformbeheerder (komt erna), Default Restaurant/configuratie, integraties en geheimenopslag (alleen de bestaande
`integration_plugins` wordt dichtgezet), privacy/AVG-documenten, goedkeuringslink-verbeteringen (D5),
configureerbare rechtenmatrix, creditnota's/correctieboekingen, heropenen van dagafsluiting.

**STOP — wachten op expliciete GO per stap.**
