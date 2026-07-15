# Restaurant Business Accounting Platform — Architectuur Blueprint

Status: ONBEVESTIGD (nog geen implementatie gestart)
Versie: 0.1 — Blueprint fase

---

## 1. TECHSTACK BESLISSING

Afgeleid uit projectdocumentatie (niet aangenomen):
- Projectvisie eist een **relationele database met auditlog** → PostgreSQL.
- Systeemprompt (sectie 11) eist iPhone-first, Working Copy + GitHub + Vercel compatibel.
- Systeemprompt (sectie 12) staat zowel Firebase als Supabase toe, maar Supabase gebruikt native PostgreSQL — dit sluit direct aan op de projectvisie.

**Gekozen stack:**

| Laag | Keuze | Reden |
|---|---|---|
| Frontend | Next.js (App Router) + TypeScript | Vercel-native, PWA-geschikt, serverless |
| Styling | Tailwind CSS | Snel, mobile-first, iPhone safe-area support |
| Backend | Supabase (PostgreSQL, Auth, Storage, Edge Functions, Realtime) | Relationeel, auditlog-geschikt, multi-tenant-ready |
| Hosting | Vercel | Serverless, iPhone-first deploy zonder terminal |
| Git-workflow | GitHub + Working Copy | Vereist door systeemprompt sectie 11 |
| Bestandsopslag | Supabase Storage | Bonafbeeldingen, PDF-facturen, bijlagen |
| PWA | next-pwa / manifest + service worker | Installeerbaar via Safari, iOS 16.4+ |

Dit blijft **ONBEVESTIGD** totdat jij akkoord geeft — dit is de eerste plek waar ik je bevestiging nodig heb.

**Aanvullend ontwerpprincipe: API-first.** Alle functionaliteit wordt eerst als API ontworpen (Next.js API routes / Supabase). De webinterface is één van de consumenten van die API — toekomstige mobiele apps of externe integraties gebruiken dezelfde laag zonder duplicatie.

---

## 2. SYSTEEMARCHITECTUUR (Engine → Module → Service → Feature → UI)

```
Engine (Next.js app + Supabase backend)
│
├── EVENT BUS (kernlaag — geen module, maar ruggengraat van het systeem)
│   Modules publiceren domain events, andere modules abonneren zich.
│   Voorbeelden: ReceiptLinked, InvoiceGenerated, PaymentReceived,
│                ImportFailed, TabClosed, OcrCompleted
│   Geen directe module-naar-module aanroepen meer voor side-effects
│   (notificeren, loggen, workflows triggeren) — alles via events.
│
├── Module: Bedrijvenbeheer
│   ├── Service: companies, departments, cost-centers, projects
│   └── Feature/UI: bedrijf aanmaken, afdeling toevoegen, project koppelen
│
├── Module: Open Rekeningen
│   ├── Service: tabs, visitors, linking
│   └── Feature/UI: rekening openen/sluiten, bon koppelen
│   └── Publiceert: TabOpened, TabClosed
│
├── Module: Receipt Engine (opgesplitst, klein en onderhoudbaar)
│   ├── Receipt Manager      → centrale coördinatie
│   ├── Receipt Storage      → opslag ruwe bon + metadata
│   ├── Receipt Validation   → controle op volledigheid/consistentie
│   ├── Receipt Linking      → koppeling aan open rekening/bedrijf
│   ├── Receipt Scanner      → barcode/QR-inlezing
│   ├── Receipt OCR          → AI-extractie uit foto
│   └── Receipt Import       → koppelt binnenkomende data uit Integration Engine
│   └── Publiceert: ReceiptLinked, OcrCompleted
│
├── Module: Integration Engine (plugin-gebaseerd, generiek)
│   ├── Plugin-interface: elke connector implementeert dezelfde contract
│   ├── POS Plugins          → per kassasysteem, hot-swappable
│   ├── Accounting Plugins
│   ├── Payment Plugins
│   ├── Reservation Plugins
│   ├── Loyalty Plugins
│   ├── Import Engine        → CSV/Excel/XML/JSON/TXT
│   ├── Export Engine        → boekhoudkoppelingen, rapportages
│   └── Webhooks             → in- en uitgaande events
│   └── Publiceert: ImportFailed, ImportCompleted, ConnectorError
│
├── Module: Workflow Engine (configuratie-gedreven)
│   ├── Service: facturatie-regels per bedrijf, gelezen uit configuratie
│   │   (frequentie, btw-afwijkingen, goedkeuringsflow — geen maatwerkcode)
│   └── Feature/UI: workflowregels beheren per bedrijf/afdeling
│   └── Luistert naar: TabClosed → Publiceert: InvoiceRequested
│
├── Module: Facturatie
│   ├── Service: invoice-generator
│   └── Feature/UI: factuur genereren, verzenden, historie
│   └── Luistert naar: InvoiceRequested → Publiceert: InvoiceGenerated
│
├── Module: Document Engine (generiek, configuratie-gedreven templates)
│   ├── Service: pdf-generator, template-engine
│   └── Documenttypes: facturen, creditfacturen, offertes, pakbonnen, rapportage-exports
│
├── Module: Notification Engine (luistert op de Event Bus, geen directe aanroepen)
│   ├── Service: notification-dispatch (mail/in-app/push)
│   ├── Luistert naar: InvoiceGenerated, PaymentReceived, ImportFailed,
│   │                   OcrCompleted (bij lage zekerheid), ConnectorError
│   │
│   └── Email Engine (sub-module, provider-onafhankelijk — governance 6.4)
│       │
│       ├── Email Provider Interface  → enige contract dat Notification Engine kent
│       │   └── Resend Provider       → standaardimplementatie (uitwisselbaar)
│       │       └── Toekomstige providers: SMTP, Microsoft 365, enz.
│       │
│       └── Per-restaurant instellingen: afzendernaam, afzendadres, reply-to,
│           eigen domein / platformdomein (fallback)
│
├── Module: Betalingen & Boekhouding
│   ├── Service: payments, accounting-export
│   └── Feature/UI: openstaand saldo, betaalstatus
│   └── Publiceert: PaymentReceived
│
├── Module: Rapportages & Dashboard
│   ├── Service: reporting-engine
│   └── Feature/UI: omzet, top-klanten, BTW-overzicht
│
├── Module: Audit & Activity Engine (luistert op alle events)
│   ├── Audit Log     → wat is er gewijzigd (data-niveau, verplicht)
│   └── Activity Log  → wie deed wat, wanneer, met welk resultaat
│
├── Module: Monitoring & Observability (nieuw, vanaf dag 1)
│   ├── Foutlogging (error tracking)
│   ├── Performance-metrics
│   ├── API-status / connectorstatus
│   └── Achtergrondtaken-status (imports, OCR-jobs, e-mailverzending)
│
├── Module: AI Analyse (later, sectie EXPERIMENTAL)
│   └── Service: anomaly-detection, ocr-assist, forecasting
│
└── Module: Beheer
    ├── Service: roles, permissions, multi-restaurant
    └── Feature/UI: gebruikersbeheer, rechten
```

Elke module is onafhankelijk uitbreidbaar en communiceert uitsluitend via services of de Event Bus (geen directe UI→database calls, geen directe module→module aanroepen voor side-effects), conform sectie 4.

**Belangrijk architectuurprincipe (nieuw):** Notification Engine, Audit & Activity Engine en Monitoring zijn *pure event-luisteraars* — ze bevatten geen kennis van de modules die events publiceren. Een nieuwe module hoeft alleen events te publiceren om automatisch genotificeerd, gelogd en gemonitord te worden. Dit voorkomt dubbele utilities (sectie 7) en houdt modules volledig los gekoppeld.

---

## 3. DATABASE — KERNENTITEITEN (hoog niveau, relationeel)

```
restaurants (SaaS tenant root)
├── users (rollen: owner, manager, admin, service, kitchen)
├── companies (bedrijven)
│   ├── departments (afdelingen)
│   ├── cost_centers (kostenplaatsen)
│   ├── projects (projectcodes)
│   └── contacts (contactpersonen)
├── open_tabs (open rekeningen)
│   └── linked to: company, department, cost_center, project, visitor(s)
├── receipts (bonnen)
│   ├── receipt_lines (productregels)
│   └── source: api | import | qr | ocr | manual
├── invoices (facturen)
│   ├── invoice_lines
│   └── status: draft | sent | paid | overdue
├── documents (generiek: factuur, creditfactuur, offerte, pakbon, export)
│   └── type, gekoppeld record, storage_path
├── workflow_rules (per bedrijf/afdeling: frequentie, goedkeuring vereist)
├── configurations (config-driven bedrijfsregels: btw-afwijkingen,
│   documenttemplates, notificatie-instellingen — per restaurant/bedrijf)
├── payments
├── notifications (type, ontvanger, status, trigger-event)
├── email_settings (per restaurant: provider (default 'resend'), sender_name,
│   sender_email, reply_to, custom_domain, gebruikt platformdomein als fallback)
├── domain_events (event-log: type, payload, gepubliceerd_door, timestamp
│   — dient ook als audit-trail voor de Event Bus zelf)
├── audit_log (alle wijzigingen, verplicht per projectvisie)
└── activity_log (wie deed wat, wanneer — los van audit_log)
```

Multi-tenant via `restaurant_id` op alle tabellen (Row Level Security in Supabase) — dit maakt het SaaS-ready zonder architectuurwijziging later.

**Event Bus implementatie:** in Supabase te realiseren via Postgres triggers + `pg_notify`, of via een lichte in-app event-emitter die naar Supabase Edge Functions publiceert. Voor Fase 1 volstaat een eenvoudige in-app emitter — de `domain_events`-tabel zorgt dat er geen architectuurwijziging nodig is wanneer dit later naar een echte message queue (bijv. voor schaalvergroting) moet.

---

## 4. FASERING (bouwvolgorde — voorkomt feature sprawl, sectie 18)

Per sectie 8 (Bestandsstrategie): elke fase = eigen module/wijziging, niet alles ineens.

Belangrijk: de nieuwe cross-cutting engines (Event Bus, Notification, Audit & Activity, Monitoring) worden als **lichte skeletons vanaf Fase 1** meegebouwd — niet pas later toegevoegd. Zo voorkomen we exact de refactor die je wilde vermijden. Ze starten simpel en groeien mee.

**Fase 1 — MVP Kern (fundament, geen kassa-koppeling nodig)**
- Event Bus: basisversie (in-app emitter + `domain_events`-tabel) — actief vanaf dag 1
- Auth + Beheer (rollen)
- Bedrijven, Contactpersonen, Afdelingen, Kostenplaatsen, Projecten
- Open rekeningen
- Receipt Engine: alleen Receipt Manager + Storage + Validation + Linking, invoerpad = **handmatig**
- Workflow Engine: basisversie, regels uit `configurations`-tabel (config-driven vanaf start)
- Facturatie: genereren via Document Engine (alleen factuur-type actief)
- Notification Engine: luistert op `InvoiceGenerated`, `PaymentReceived`
- Audit & Activity Engine: actief vanaf dag 1 (verplicht, niet later toevoegen)
- Monitoring: basale foutlogging + API-status
- Dashboard: basiscijfers
- Alle functionaliteit als API-route ontworpen (API-first), UI is consument daarvan
- Back-up: Supabase point-in-time recovery ingeschakeld, opslagbeleid documenten
- Beveiliging: rate limiting op API-routes, 2FA verplicht voor owner/manager-rol, encryptie gevoelige velden

**Fase 2 — Automatisering bonverwerking (Integration Engine als plugin-systeem)**
- Integration Engine: plugin-interface vastleggen, Import Engine als eerste plugin (CSV/Excel/XML/JSON/TXT), Webhooks
- Receipt Scanner (Barcode/QR)
- POS Plugins (per kassasysteem, zelfde interface — nieuw kassasysteem = nieuwe plugin)
- Notification Engine: luistert op `ImportFailed`, `ConnectorError`
- Monitoring: connectorstatus + achtergrondtaken toevoegen

**Fase 3 — OCR**
- Receipt OCR: foto van papieren bon → AI-extractie → medewerkercontrole
- Notification Engine: luistert op `OcrCompleted` (bij lage zekerheid)

**Fase 4 — Workflow & Document verdieping**
- Workflow Engine: wekelijks/maandelijks/per-project facturatie, goedkeuringsstappen (config-driven)
- Document Engine: creditfacturen, offertes, pakbonnen, rapportage-exports (configureerbare templates)
- Export Engine (Accounting Plugins)
- Rapportages verdieping

**Fase 5 — AI Analyse module (EXPERIMENTAL label)**
- Fraude/afwijkingsdetectie, dubbele bonnen, voorspellingen
- Payment Plugins, Loyalty Plugins, Reservation Plugins

Elke fase levert een werkend, bruikbaar systeem op — geen halve implementaties (sectie 7/9).

---

## 5. GUARDIAN MODE — VOOR ELKE FASE VERPLICHT

Voordat een fase geïmplementeerd wordt, doorloop ik:
1. Root Cause / Doel-analyse
2. Dependency-analyse (welke modules/services al nodig)
3. Impact-analyse (wat raakt dit)
4. Regressierisico (alleen relevant vanaf fase 2, fase 1 is nieuw)

---

## 6. GOVERNANCE-PRINCIPES (vastgelegd vóór implementatie, niet later heronderhandelen)

**6.1 Event Bus — intern, stabiele contracten**
MVP gebruikt een interne eventbus (in-app emitter + `domain_events`-tabel). Event-namen en payload-structuur (`ReceiptLinked`, `InvoiceGenerated`, etc.) worden behandeld als onderdeel van de architectuur — niet los aangepast. Migratie naar een externe message broker (bij schaal) mag de modules zelf niet raken; alleen de transportlaag onder de Event Bus verandert.

**6.2 Database als enige bron van waarheid**
PostgreSQL (Supabase) is de enige bron van waarheid. `domain_events`, caches en toekomstige zoekindexen zijn altijd afgeleiden, nooit leidend. Bij conflict wint de database. Dit voorkomt synchronisatieproblemen tussen event-log en werkelijke status.

**6.3 Versiebeheer van integraties**
Elke plugin (POS, boekhouding, betalingen, reservering, loyalty) krijgt een eigen versie + compatibiliteitsinformatie (`plugin_version`, `min_core_version`). Oude en nieuwe connectorversies mogen tijdelijk naast elkaar bestaan wanneer een leverancier zijn API wijzigt — geen gedwongen big-bang migratie.

**6.4 E-mailprovider-onafhankelijkheid**
De applicatie mag nooit afhankelijk zijn van één e-mailprovider — hetzelfde principe als kassa-onafhankelijkheid (projectvisie, "Belangrijk ontwerpprincipe"). De Notification Engine kent uitsluitend de **Email Provider Interface**; Resend is de standaardimplementatie daarachter. Een andere provider (SMTP, Microsoft 365) toevoegen betekent alleen een nieuwe implementatie van die interface schrijven — geen wijziging aan de Notification Engine zelf.

## 7. NIET-FUNCTIONELE VEREISTEN (vanaf Fase 1, geen latere toevoeging)

**7.1 Back-up & herstel**
- Automatische dagelijkse databaseback-ups (Supabase point-in-time recovery)
- Opslagbeleid voor documenten/bonafbeeldingen (retentie, redundantie)
- Gedocumenteerde herstelprocedure, getest vóór productie

**7.2 Beveiliging**
- Encryptie van gevoelige gegevens (at rest + in transit — Supabase default + expliciete controle op gevoelige velden)
- Rate limiting op API-routes
- Audit van inlogpogingen (onderdeel van Audit & Activity Engine)
- Tweefactorauthenticatie verplicht voor beheerdersrollen (owner/manager)

**7.3 Contextuele in-app uitleg**
Elke module die voor de gebruiker niet vanzelfsprekend is (met name optionele velden, volgorde-afhankelijkheden, of koppelingen tussen modules) krijgt een kort, inklapbaar uitlegblok direct in de UI ("Hoe werkt dit?") — geen aparte handleiding die apart opgezocht moet worden. Vaste regel: wanneer de onderliggende logica van een module verandert, wordt dit uitlegblok in dezelfde wijziging bijgewerkt — net zoals `docs/architecture.md` en `README.md` worden bijgehouden. Voorbeeld: de uitleg op de bedrijfsdetailpagina over Afdeling/Kostenplaats/Project in relatie tot Open Rekeningen (toegevoegd bij implementatie, zie sectie 8).

## 8. UITBREIDING: APPROVAL ENGINE + BEDRIJFSREFERENTIES (goedgekeurd, klant-specificatie)

Status: **goedgekeurde architectuuruitbreiding**, aangeleverd als technische master-spec.
Volgt hetzelfde patroon als de rest: Config-driven → Plugin-based → Audit-veilig → Uitbreidbaar.

### 10.1 Bedrijfsreferenties (Company Codes)

Eén generieke tabel i.p.v. een aparte tabel per codetype (routecode, WBS/WBF, kostendrager,
budgetcode, enz.) — nieuwe codetypes moeten toegevoegd kunnen worden zonder migratie.

```
company_codes
├── id, company_id, type (vrije string: 'routecode'|'wbs_wbf'|'budgetcode'|...)
├── code, description, is_active
```

### 10.2 Verplichte velden per bedrijf

Geen harde velden in code — hergebruikt de bestaande `configurations`-tabel (key
`receipt_fields`, jsonb) die al in Fase 1 is gebouwd. Voorbeeld: `{"routecode": true,
"wbs_wbf": true, "kostenplaats": false}`. Het bon-formulier past zich hierop aan.

### 10.3 Approval Engine

Zelfde interface-patroon als de Email Engine (governance 6.4): een centrale engine die
uitsluitend de **Approval Provider Interface** kent, met vijf uitwisselbare providers:
PIN, E-mail (hergebruikt bestaande Email Engine), QR, Digitale handtekening, Restaurant
bevestigt. Per bedrijf instelbaar via `approval_settings` (method, is_required, auto_lock).

```
Approval Engine
      │
      ▼
Approval Provider Interface
      │
      ├── PIN Provider
      ├── Email Provider       (hergebruikt Email Engine)
      ├── QR Provider
      ├── Signature Provider   (iPad/Apple Pencil/touch)
      └── Restaurant-confirms Provider
```

### 10.4 Uitgebreide statusworkflow (bonnen)

`draft → submitted → pending_approval → approved → locked`

Na `locked`: geen normale wijzigingen meer — alleen via de Audit & Activity Engine, met
gebruiker/tijdstip/oude+nieuwe waarde/reden. Dit is exact hetzelfde beveiligingspatroon
dat al gebouwd is voor gefactureerde rekeningen (v1.17-v1.20), nu toegepast op het
goedkeuringsmoment vóór facturatie i.p.v. erna.

**Reconciliatie met bestaand schema:** de huidige `receipts.status` (`draft`/`validated`/
`linked`) blijft ongewijzigd van gedrag voor bedrijven zonder Approval-configuratie — de
nieuwe statuswaarden worden additief toegevoegd aan de constraint, niet vervangend. Zo
blijft het bestaande handmatige pad (Fase 1) volledig intact terwijl grotere/zakelijke
klanten straks de uitgebreide flow kunnen gebruiken.

### 10.5 Database — Approval Engine

```
approval_settings (per bedrijf: method, is_required, auto_lock)
approvals (per bon: method, approved_by, approved_at, status, signature_data,
           verification_code)
```

### 10.6 Implementatievolgorde (klant-goedgekeurd)

| Fase | Inhoud | Afhankelijkheid |
|---|---|---|
| **A** | `company_codes`-tabel, verplichte-velden-config, formulierondersteuning, status-uitbreiding (schema-only, geen gedragswijziging) | Geen — kan direct |
| **B** | Approval Engine basis: Provider Interface, PIN-provider, Restaurant-bevestigt-provider, lock-mechanisme | Wacht op klantkeuze welke methode eerst |
| **C** | E-mail-provider (hergebruikt Email Engine), QR-provider | Na B |
| **D** | Digitale handtekening + uitgebreide audit-logging | Na C, meest hardware-specifiek |

### 10.7 Fase B — Implementatieplan (vastgelegd vóór bouwen, Guardian Mode)

**Bevindingen uit codebase-review (vooraf, conform de gevraagde werkwijze):**
- De `EventBus`-class in `lib/events/event-bus.ts` wordt nergens aangeroepen. Alle bestaande
  routes schrijven direct naar `domain_events` via `supabase.from("domain_events").insert(...)`.
  Fase B volgt dit **daadwerkelijk gebruikte** patroon, niet de ongebruikte class.
- Er bestaat nog geen gecodeerde Email Provider Interface — alleen gedocumenteerd (governance
  6.4). Resend loopt via Supabase Auth SMTP, niet via eigen app-code. Er is dus geen bestaand
  provider-codepatroon om te kopiëren; de Approval Provider Interface is de eerste van dit soort.
- Fase A (migratie 0006) dekt het meeste schema al: `approval_settings` en `approvals` bestaan,
  `receipts.status` accepteert al de uitgebreide workflow-waarden. Alleen een kleine uitbreiding
  nodig: `pin_hash` op `approval_settings`, `requested_at`/`metadata`/`expired` op `approvals`.

**Vertical slice:** `Receipt → Approval Request → PIN/Restaurant Confirmation → Approved → Locked → Audit`,
volledig werkend end-to-end, niet alleen schema/instellingen.

**Nieuwe bestanden:**
| Bestand | Doel |
|---|---|
| `supabase/migrations/0007_approval_engine_extend.sql` | `pin_hash`, `requested_at`/`metadata`/`expired` |
| `lib/approval/types.ts` | `ApprovalProvider`-interface, `ApprovalMethod`-type |
| `lib/approval/providers/pin-provider.ts` | PIN hashen/verifiëren (Node `crypto.scrypt`, geen extra dependency) |
| `lib/approval/providers/restaurant-confirm-provider.ts` | Triviale provider |
| `app/api/companies/[id]/approval-settings/route.ts` | GET/PUT — methode + PIN instellen (write-only) |
| `app/api/receipts/[id]/request-approval/route.ts` | POST — bon naar `pending_approval` |
| `app/api/receipts/[id]/approve/route.ts` | POST — dispatcht naar provider, bij succes `approved → locked` |
| `ApprovalSettingsSection` (in `sub-entities.tsx`) | UI: aan/uit, methode, PIN instellen |

**Bestaande bestanden die wijzigen:**
- `app/api/open-tabs/[id]/receipts/route.ts` — na aanmaken automatisch `request-approval` triggeren indien vereist
- `app/api/receipts/[id]/route.ts` — bewerken/verwijderen ook blokkeren bij `status = locked`
- `app/api/open-tabs/[id]/generate-invoice/route.ts` — weigeren bij een gekoppelde bon met `pending_approval`
- `receipts-section.tsx` — toont status + juiste invoerveld (PIN/bevestigknop), bevat zelf geen providerlogica
- `open-tabs/[id]/page.tsx` — haalt `approval_settings` op, geeft door aan `ReceiptsSection`

**Risico's:**
- PIN nooit plat opslaan/teruggeven — alleen hash-vergelijking server-side
- Bestaande bonnen (`status: linked`) blijven ongemoeid — additief, geen data-migratie
- Statusovergangen strikt server-side afgedwongen (zelfde patroon als het `invoiced`-lock-mechanisme, v1.17-v1.20)

### 10.8 Fase A.5 — Teambeheer / User Management Module (vastgelegd, goedgekeurd met aanpassingen)

**Verplicht vóór Fase B**: `approved_by` in de Approval Engine heeft pas waarde met échte,
losse gebruikersaccounts per medewerker i.p.v. één gedeeld eigenaarsaccount.

**Klant-aanpassingen op het oorspronkelijke plan:**
1. `permissions.ts` wordt vanaf nu **standaard voor alle nieuwe code** — nooit meer losse
   `if (user.role === ...)`-checks, altijd `requireRole()`/`hasPermission()`. Bestaande routes
   worden niet in dezelfde stap omgebouwd (scope-bewaking), maar elke nieuwe route vanaf nu wel.
2. De Team Service is **generiek gebruikersbeheer**, geen "invite service": `listTeam`,
   `inviteUser`, `updateRole`, `activateUser`, `deactivateUser`, `removeUser` — zodat
   `resetPassword`/`resendInvitation`/`enable2FA`/`updateProfile` er later zonder
   architectuurwijziging bij kunnen.
3. **Gebouwd als generieke User Management Module**, niet als restaurant-specifieke pagina:

```
lib/user-management/
├── role-helpers.ts        → roldefinities + permissie-matrix
├── permission-service.ts  → requireRole()/hasPermission() — centrale autorisatielaag
├── user-repository.ts     → data-access (rechtstreekse Supabase-queries)
├── invitation-service.ts  → uitnodigen via Supabase admin-API
├── team-service.ts        → orchestreert repository + invitation + permissions + events
└── events.ts              → publiceert UserInvited/UserRoleChanged/UserActivated/UserDeactivated
```
De UI heet "Team", de architectuur eronder is generiek en herbruikbaar voor andere modules.

**Nieuwe migratie:** `0008_team_management.sql` — `is_active` op `users`, RLS-policy zodat
teamleden van hetzelfde restaurant elkaar mogen zien (nooit gebruikers van een ander restaurant).

**Nieuwe bestanden (naast de module hierboven):**
- `lib/supabase/admin.ts` — service-role client, uitsluitend server-side
- `app/api/team/route.ts` (GET/POST), `app/api/team/[id]/route.ts` (PATCH/DELETE)
- `app/(dashboard)/team/page.tsx` + formulieren

**Bestaande bestanden die wijzigen:**
- `lib/events/types.ts` — 4 nieuwe events
- `middleware.ts` — gedeactiveerde gebruikers blokkeren
- `dashboard/page.tsx` — Activity Log toont naam i.p.v. alleen actie
- `layout.tsx` — "Team"-navigatielink

**Risico's/guards:**
- Service-role key: eerste gebruik in app-code, nooit richting client
- Eigenaar kan zichzelf niet deactiveren/verwijderen; laatste eigenaar van een restaurant
  is altijd beschermd (expliciete guard in `team-service.ts`, niet database-afgedwongen)
- FK-constraints (`activity_log.user_id`, `audit_log.changed_by`) voorkomen al hard
  verwijderen van gebruikers met historie — nette foutafhandeling i.p.v. 500-fout
- Uitnodigingsmail deelt de Resend-testlimiet met wachtwoord-reset (bekend, v1.3)

**Status: goedgekeurd, bouwen.**

**v1.23** — Fase A.5 geïmplementeerd: Teambeheer / User Management Module (klant-goedgekeurd, met aanpassingen):
- **User Management Module** gebouwd als generieke architectuur (`lib/user-management/`):
  `role-helpers.ts` (permissie-matrix), `permission-service.ts` (`requireRole`/`hasPermission`
  — centrale autorisatielaag, verplicht voor alle nieuwe routes vanaf nu), `user-repository.ts`
  (data-access), `invitation-service.ts` (Supabase admin-API), `team-service.ts` (orchestratie:
  listTeam/inviteUser/updateRole/activateUser/deactivateUser/removeUser — bewust generiek
  genoemd, niet "invite-service", zodat resetPassword/2FA er later bij kunnen), `events.ts`
- 4 nieuwe events: `UserInvited`, `UserRoleChanged`, `UserActivated`, `UserDeactivated`
- **Guards**: eigenaar kan zichzelf niet deactiveren/verwijderen; laatste actieve eigenaar van
  een restaurant is altijd beschermd tegen degraderen/deactiveren/verwijderen; FK-constraints
  (bestonden al) voorkomen hard verwijderen van gebruikers met historie — nu netjes vertaald
  naar een begrijpelijke foutmelding i.p.v. ruwe database-error
- `lib/supabase/admin.ts`: **eerste gebruik van de service-role key in app-code**, strikt
  server-side, nooit richting client
- Middleware uitgebreid: gedeactiveerde gebruikers worden uitgelogd met duidelijke melding
- Dashboard Activity Log toont nu de naam van de gebruiker, niet alleen de actie
- Team-pagina (`/team`) met uitnodigen, rol wijzigen, activeren/deactiveren, verwijderen
- **Bewuste scope-afbakening**: bestaande routes (bedrijven/rekeningen/bonnen/facturen)
  zijn niet omgebouwd naar `requireRole()` — dat is een aparte, latere stap. Alleen nieuwe
  code (Team-routes) gebruikt vanaf nu de centrale autorisatielaag.
- **Nu mogelijk**: `approved_by` in de aankomende Approval Engine (Fase B) krijgt betekenis,
  want er kunnen nu losse, herkenbare accounts per medewerker bestaan

**v1.24** — Bevestiging: teamuitnodiging technisch correct, zelfde Resend-limiet als v1.3 (geen architectuurwijziging):
- Uitnodigingsflow (`inviteUser` → Supabase admin-API) bevestigd correct werkend — faalt
  alleen op mailverzending naar niet-geverifieerde testadressen, exact zoals bij
  wachtwoord-reset (v1.3). Geen codefout.
- **Bijzonderheid ontdekt**: bij een mislukte uitnodiging (mailfout) heeft Supabase het
  `auth.users`-record al aangemaakt vóórdat de mail faalt — onze code stopt vóór de
  koppeling in `public.users`, wat een "weeskopie" achterlaat (auth-account zonder profiel).
  Onschuldig zolang hetzelfde adres niet nogmaals geprobeerd wordt (geeft dan "already
  registered"). Op te ruimen zodra nodig via Supabase Dashboard → Authentication → Users.
- Volledige end-to-end bevestiging (mail daadwerkelijk aankomt bij een collega) wacht,
  net als facturen mailen, op het geverifieerde Resend-domein.

**v1.24a** — Bugfix: RLS-recursie in migratie 0008 (kritiek, geen architectuurwijziging):
- De nieuwe policy "users can see team members" (migratie 0008) queryde de `users`-tabel
  vanuit een policy die zelf óp `users` staat → oneindige recursie. Omdat vrijwel elke
  andere tabel via `users` de eigen `restaurant_id` opzoekt, brak dit **alle** schermen
  (zelfs Bedrijven), niet alleen Team.
- Oplossing: `supabase/migrations/0009_fix_rls_recursion.sql` — een `SECURITY DEFINER`-
  functie (`my_restaurant_id()`) die de RLS-check omzeilt bij het opzoeken van de eigen
  restaurant_id, het standaard Postgres/Supabase-patroon voor zelfreferentiële policies.
- Les: een policy op tabel X die tabel X zelf raadpleegt (zelfs onrechtstreeks via een
  subquery) is een directe recursie-kandidaat — voortaan bij zelfreferentiële RLS-policies
  altijd een `SECURITY DEFINER`-functie gebruiken i.p.v. een inline subquery.

**v1.25** — Implementatie-update: testaccount bevestigd werkend, herbruikbaar script toegevoegd:
- `stuctech+test1@gmail.com` (rol bediening) is geactiveerd door het "wees"-account uit v1.24
  alsnog een wachtwoord + profielkoppeling te geven — bevestigd inlogbaar
- `supabase/scripts/create-test-account.sql` toegevoegd — **bewust geen migratie** (geen
  schemawijziging, maar testdata), apart gehouden van `supabase/migrations/` zodat de
  migratienummering zuiver blijft. Herbruikbaar voor meerdere rollen/testers.
- Doel: de klant kan nu zelf met een tweede account inloggen en het multi-user-gedrag
  beoordelen, zonder te hoeven wachten op het Resend-domein

**v1.26** — Bugfix: uitnodigingslink miste koppeling aan wachtwoord-instellen (geen architectuurwijziging, belangrijk vóór echte uitnodigingen):
- Ontdekt bij een operationele vraag ("krijgt de medewerker een mail en kan die met eigen
  gegevens inloggen?"): `inviteUserByEmail` werd zonder `redirectTo` aangeroepen, waardoor de
  uitnodigingslink iemand mogelijk direct via een tijdelijke sessie had ingelogd zonder ooit
  een eigen wachtwoord te kiezen — bij een volgend bezoek zouden ze dan buitengesloten zijn
  (geen wachtwoord ingesteld).
- Oplossing: `redirectTo` wijst nu expliciet naar `/reset-password` — dezelfde pagina die al
  voor wachtwoord-vergeten gebruikt wordt, hergebruikt voor het instellen van het eerste
  wachtwoord bij een uitnodiging. Geen nieuwe Supabase-configuratie nodig, want die
  redirect-URL stond al op de whitelist (v1.3).
- Bevestigt nogmaals de waarde van operationele "hoe werkt dit in de praktijk"-vragen — deze
  bug was niet zichtbaar in een technische test (de uitnodiging zelf "lukte" volgens de API),
  alleen in het doordenken van de complete gebruikerservaring.

**v1.27** — Bugfix: handmatige `auth.users`-insert faalde stil bij inloggen (geen architectuurwijziging):
- Testaccount leek volledig te werken (kwam voor in Team-lijst, wachtwoord-reset/uitnodigen
  API's gaven geen fout), maar inloggen zelf faalde met "Inloggen mislukt" — zonder duidelijke
  serverfout, want dit is Supabase Auth's eigen interne verwerking, niet onze applicatiecode.
- Oorzaak: `confirmation_token`/`recovery_token`/`email_change*`-kolommen op `null` i.p.v. een
  lege string (`''`) breken Supabase's interne inlogverwerking, ook al lijkt de rij verder
  volledig geldig (wachtwoord-hash correct, `email_confirmed_at` gezet).
- Oplossing: `supabase/scripts/create-test-account.sql` bijgewerkt met expliciete lege strings
  voor alle token-kolommen en de vereiste `raw_app_meta_data`/`raw_user_meta_data`-velden.
- Les: **altijd daadwerkelijk inloggen testen** na een handmatige `auth.users`-insert, niet
  alleen controleren of de rij bestaat of of gekoppelde API's (reset/invite) foutloos reageren
  — die testen een ander code-pad dan het daadwerkelijke inlogproces zelf.

**v1.28** — Fase B geïmplementeerd: Approval Engine core + PIN + Restaurant-bevestigt (klant-goedgekeurd, volgens plan sectie 10.7):
- **Volledige vertical slice werkend**: `Receipt → Approval Request → PIN/Restaurant
  Confirmation → Approved → Locked → Audit`, niet alleen schema/instellingen
- `lib/approval/`: `types.ts` (Approval Provider Interface), `approval-service.ts`
  (enige aanspreekpunt voor aanroepers — kent alleen "goedkeuring nodig ja/nee", nooit
  een concrete provider), `providers/pin-provider.ts` (Node `crypto.scrypt`, geen extra
  dependency — zelfde afweging als `pdf-lib`), `providers/restaurant-confirm-provider.ts`
- Migratie 0007: vult de kleine gaten uit Fase A aan (`pin_hash`/`pin_salt`,
  `requested_at`/`metadata` op `approvals`, `expired`-status)
- 3 nieuwe events: `ApprovalRequested`, `ApprovalCompleted`, `ReceiptLocked`
- **Integratiepunten in bestaande code** (per plan, geen nieuwe architectuur):
  - Bon aanmaken: automatisch `pending_approval` als het bedrijf dat vereist
  - Bon bewerken/verwijderen: geblokkeerd bij `status = locked` (naast de bestaande
    `invoiced`-blokkade van de rekening zelf — twee onafhankelijke vergrendelingsniveaus)
  - Factuur genereren: weigert als een gekoppelde bon nog `pending_approval` is
- UI: `ApprovalSettingsSection` (bedrijfspagina — methode + PIN instellen, write-only),
  `ApprovalBlock` (bonnenlijst — toont PIN-veld of bevestigknop; bevat zelf **geen**
  providerlogica, roept alleen `/approve` aan met wat de gebruiker invoerde)
- Klant-eis nageleefd: geen directe koppeling Receipt Manager ↔ Approval Providers —
  alle communicatie loopt via `approval-service.ts`

**v1.29** — Bugfix: gesloten rekeningen konden nog nieuwe bonnen krijgen (geen architectuurwijziging):
- Ontdekt bij een operationele vraag: eerder communiceerde ik dat "gesloten" betekent
  "gast is klaar, geen bon meer bij" (bij de invoering van de statusfilter, v1.9), maar
  de server blokkeerde alleen op `status = invoiced`, niet op `status = closed` — een
  inconsistentie tussen beschreven en afgedwongen gedrag.
- Oplossing: `/api/open-tabs/[id]/receipts` (POST) staat nu alleen nog bonnen toe bij
  `status = open`; UI-knop "+ Bon toevoegen" verdwijnt nu ook bij `closed` (voorheen alleen
  bij `invoiced`), met aparte, duidelijke meldingen per situatie.
- Bewuste keuze: **bewerken/verwijderen van al bestaande bonnen** blijft mogelijk tussen
  `closed` en `invoiced` in — alleen het toevoegen van *nieuwe* bonnen wordt geblokkeerd
  bij sluiting. Dat behoudt de ruimte om een foutje te corrigeren vóór facturatie.

## 9. UITBREIDING: DAILY CLOSING ENGINE (goedgekeurd, klant-specificatie)

Status: **goedgekeurd, direct geïmplementeerd** (v1.30).

Bewust **geen** Dashboard-uitbreiding — het Dashboard is managementinformatie (omzet,
trends, activiteit); Daily Closing is een operationele controle die dagelijks vóór
kassa-afsluiting wordt uitgevoerd. Twee verschillende verantwoordelijkheden, twee modules.

```
lib/daily-closing/daily-closing-service.ts   → verzamelt data uit andere modules
supabase/migrations/0010_daily_closing.sql   → daily_closings-tabel
app/api/daily-closing/route.ts               → GET (status), POST (dag afsluiten)
app/(dashboard)/daily-closing/page.tsx       → controlepagina
```

De service **verzamelt** informatie uit Receipt Manager / Open Rekeningen / Approval Engine
/ Invoice Engine — neemt nooit hun logica over, alleen lezen (governance 6.2: database is
bron van waarheid, geen dubbele state).

**Bekende, bewust benoemde gaten (geen verzonnen "✓" tonen waar het niet klopt):**
- Contante/pin-omzet-splitsing: n.v.t. — geen betaalmethode-registratie op bonnen (nog)
- "Afgekeurde bonnen"-teller: er bestaat geen afkeuren-actie in de Approval Engine (alleen
  goedkeuren) — deze teller toont altijd 0, geen echte controle totdat dat gebouwd is
- "Niet gekoppelde/ontbrekende bonnen": hoort bij Fase 2 (Import Engine/kassa-koppeling),
  n.v.t. in de huidige handmatige flow

**Toegang:** nieuwe permissie `MANAGE_DAILY_CLOSING` (eigenaar/manager), zelfde patroon als
`APPROVE_RECEIPTS`.

**Bewust uitgesteld** (stond zelf al onder "Later" in de klant-spec): heropenen van een
afgesloten dag. Tabel is er klaar voor (`reopened_at`/`reopened_by`-kolommen), UI nog niet.

**v1.30** — Daily Closing Engine geïmplementeerd (klant-goedgekeurd, zelfstandige module, geen Dashboard-uitbreiding):
- `lib/daily-closing/daily-closing-service.ts`: verzamelt data uit Receipt Manager, Open
  Rekeningen, Approval Engine en Invoice Engine — leest alleen, neemt geen logica over
  (governance 6.2)
- Migratie 0010: `daily_closings`-tabel, met kolommen al klaar voor toekomstige heropening
  (`reopened_at`/`reopened_by`), UI daarvoor bewust nog niet gebouwd (klant-spec noemde dit
  zelf al "Later")
- Nieuwe permissie `MANAGE_DAILY_CLOSING` (eigenaar/manager), zelfde patroon als
  `APPROVE_RECEIPTS`; bekijken via bestaande `VIEW_REPORTS`
- Nieuw event: `DayClosed`
- **Bewust eerlijke "n.v.t."-markeringen** i.p.v. valse ✓: afkeuren van bonnen bestaat nog
  niet in de Approval Engine (alleen goedkeuren), kassa-import/ontbrekende-bonnen-detectie
  hoort bij Fase 2, betaalmethode (contant/pin) wordt nog niet per bon vastgelegd — deze
  controles tonen expliciet "niet van toepassing", niet een misleidende groene vink
- Onderscheid met Dashboard nu scherp: Dashboard = managementinformatie (maandomzet,
  trends, top bedrijven), Daily Closing = operationele controle vóór kassa-afsluiting

### 10.8 Fase C — Implementatieplan (vastgelegd vóór bouwen, Guardian Mode)

**Bevindingen uit codebase-review:**
- Er bestaat nog geen echte Email Provider Interface in code — alleen gedocumenteerd
  (governance 6.4). Resend loopt tot nu toe alleen via Supabase Auth (wachtwoord-reset/
  uitnodigingen). Fase C wordt de eerste echte implementatie van de Email Engine —
  herbruikbaar voor het latere factuur-mailen.
- E-mail/QR zijn fundamenteel anders dan PIN: die laatste vereist een ingelogde gebruiker
  die op een knop klikt; e-mail/QR zijn voor iemand die **niet per se inlogt** (manager op
  afstand, of later de klant zelf) — vraagt een publieke, token-based goedkeuringspagina.
- `approvals.verification_code` bestaat al sinds Fase A, ongebruikt — precies hiervoor bedoeld.

**Nieuw:**
- `lib/email/types.ts`, `lib/email/providers/resend-provider.ts`, `lib/email/email-service.ts`
  — Email Engine, eerste echte implementatie
- `app/approve/[token]/page.tsx` + `app/api/public-approve/[token]/route.ts` — publieke,
  niet-ingelogde goedkeuringsflow (token via `verification_code`)
- QR hergebruikt dezelfde link, alleen als scanbare afbeelding (externe QR-image-service,
  client-side, geen nieuwe dependency)
- Migratie 0011: `notify_email`-kolom op `approval_settings`

**Wijzigingen:** `middleware.ts` (`/approve` publiek), `approval-settings`-route en -UI,
`ApprovalBlock` (toont per methode het juiste — mailmelding, QR-afbeelding, of PIN-veld).

**Risico's:** mislukte e-mailverzending mag de bon-flow niet blokkeren (zelfde principe als
PDF-opslag, v1.14) — bon gaat gewoon naar `pending_approval`, met zichtbare waarschuwing.
Vereist een nieuwe `RESEND_API_KEY` environment variable (apart van de bestaande SMTP-config).

## 10. WIJZIGINGSHISTORIE

**v1.36** — Kritieke bugfix: GRANT-rechten ontbraken voor `service_role` (geen architectuurwijziging):
- **Symptoom**: publieke QR/e-mail-goedkeuringslink bleef "Ongeldige of verlopen link" tonen,
  ook na de v1.35-fix — terwijl de token bevestigd correct in de database stond.
- **Root cause, gevonden via tijdelijke debug-output** (Supabase-foutmelding zichtbaar
  gemaakt in de UI, sectie 15-principe): `permission denied for table approvals`. Migratie
  0004 (v1.5, de oorspronkelijke GRANT-fix) gaf destijds alleen de rol `authenticated`
  tabelrechten — niet `service_role`. Alle gewone, ingelogde requests werken via
  `authenticated` en waren dus altijd goed; de publieke goedkeuringsflow (Fase C) is de
  **eerste plek** die de service-role client daadwerkelijk gebruikt, en liep daardoor als
  eerste tegen dit gat aan.
- **Kernles herhaald, nu voor een derde rol-context**: RLS-bypass (wat service_role doet)
  en GRANT-tabelrechten zijn **twee volledig gescheiden lagen** — precies de les uit v1.5,
  nu gebleken ook te gelden voor `service_role`, niet alleen `authenticated`.
- **Oplossing**: `supabase/migrations/0012_fix_service_role_grants.sql` — zelfde patroon
  als migratie 0004, nu voor `service_role`, inclusief `alter default privileges` zodat
  toekomstige tabellen dit automatisch meekrijgen.
- **Diagnosemethode die werkte**: tijdelijk de daadwerkelijke Supabase-foutmelding
  meesturen in de API-response (i.p.v. de generieke "niet gevonden"-tekst) legde het
  probleem in één keer bloot — bevestigt nogmaals dat foutmeldingen tonen (sectie 15)
  sneller naar de waarheid leidt dan aannames testen.
- **Vervolgles**: bij elke toekomstige nieuwe rol/context die de database aanspreekt
  (bijv. een cron-job-rol, of een andere service), altijd expliciet controleren of die
  rol ook GRANT-rechten heeft — niet aannemen dat "het werkt voor authenticated" genoeg is.

**v1.35** — Bugfix: QR-goedkeuringstoken verdween bij page-refresh (geen architectuurwijziging, gevonden tijdens gebruikerstest):
- **Symptoom**: QR-code werd correct getoond direct na het aanmaken van een bon, maar na een
  page-refresh (of nieuw bezoek aan de rekening) leidde de gescande QR-code naar "Ongeldige
  of verlopen link" — terwijl `approvals.verification_code` gewoon correct in de database
  stond (bevestigd via directe SQL-diagnose).
- **Root cause**: het token leefde alleen in tijdelijke client-side React-state (uit de
  eerste POST-response bij bon aanmaken) — de pagina haalde het bij een refresh nergens
  opnieuw op, waardoor `approvalToken` `undefined` werd en de QR-afbeelding een kapotte URL
  (`.../approve/undefined`) codeerde die er nog wél als geldige QR-code uitzag.
  Diagnosemethode: directe SQL-query op `approvals` bevestigde dat de opgeslagen token
  klopte, wat de zoektocht meteen naar de weergavelaag verlegde in plaats van de opslag.
- **Oplossing**: `open-tabs/[id]/page.tsx` haalt nu bij elke laadbeurt de `approvals`-rij
  van elke bon mee (embedded query), en bepaalt het actieve `pending`-token daaruit — de
  database is en blijft de bron van waarheid (governance 6.2), niet de tijdelijke
  client-state van het moment van aanmaken.
- **Les voor vervolg**: elk token/gegenereerde-waarde die na de eerste weergave nog relevant
  moet blijven (bijv. bij een refresh, of een tweede bezoeker), moet **altijd** herleidbaar
  zijn uit de database-query van de pagina zelf — nooit alleen uit een eenmalige API-response
  die verloren gaat zodra de client-state ververst.

**v1.34** — Fase C geïmplementeerd: E-mail + QR-goedkeuring (klant-goedgekeurd, volgens plan sectie 10.8):
- **Email Engine** (`lib/email/`): eerste echte implementatie van de Email Provider Interface
  (governance 6.4) — `types.ts` (interface), `providers/resend-provider.ts` (plain fetch naar
  Resend API, geen extra dependency), `email-service.ts` (enige aanspreekpunt). Aparte
  `RESEND_API_KEY` van de bestaande Supabase Auth SMTP-configuratie.
- **Publieke, niet-ingelogde goedkeuringsflow**: `app/approve/[token]/page.tsx` +
  `app/api/public-approve/[token]/route.ts` — gebruikt `approvals.verification_code`
  (bestond al sinds Fase A, tot nu toe ongebruikt) als niet-raadbare, eenmalige token.
  Service-role client (`createSupabaseAdminClient`) nodig omdat er geen sessie is om RLS
  namens te laten gelden.
- **QR-methode**: hergebruikt exact dezelfde publieke link, alleen als scanbare afbeelding
  getoond via een externe QR-image-service (client-side `<img>`, geen nieuwe dependency).
- **Middleware uitgebreid**: `/approve` en `/api/public-approve` toegevoegd aan de publieke
  paden — belangrijk detail: de middleware-matcher dekt óók API-routes, dus beide moesten
  expliciet toegevoegd worden, niet alleen de pagina.
- **`ApprovalSettingsSection`/`ApprovalBlock` uitgebreid**: E-mail (met `notify_email`-veld)
  en QR als extra methode-opties, naast PIN/Restaurant-bevestigt.
- **Bewuste architecturale scheiding**: E-mail/QR gebruiken een fundamenteel ander pad dan
  PIN/Restaurant-bevestigt — die laatste vereisen een ingelogde gebruiker (`verify()` via de
  geauthenticeerde `/approve`-route), E-mail/QR zijn voor wie niet per se inlogt (token-link
  via de publieke route). Dit stond niet expliciet zo in het oorspronkelijke Fase B/C-plan,
  maar volgt logisch uit hoe deze methoden bedoeld zijn (`Provider 2 — Email Approval` uit de
  klant-spec: "Manager opent link, Akkoord" — geen credential-invoer).
- **Zelfde discipline als eerder**: mislukte e-mailverzending blokkeert de bon-flow niet
  (bon gaat gewoon naar `pending_approval`, met zichtbare waarschuwing) — zelfde principe
  als de factuur-PDF-opslag (v1.14).

**v1.33** — Prestatie-optimalisatie (geen architectuurwijziging, gebruikersfeedback):
- **Gemelde klacht**: knoppen "reageerden niet" (1 seconde niets, dan pas actie) — geen
  functioneel probleem, wel een reëel UX-gat, plus een oplosbare, aanwijsbare oorzaak.
- **Root cause 1 (traagheid)**: sinds v1.31 deed elke paginanavigatie meerdere aparte
  "wie ben ik, welke rol"-database-queries — middleware, layout.tsx, én elke pagina via
  `requireRole()` bevroegen dit allemaal los van elkaar.
  Oplossing: `lib/user-management/session-context.ts` — `getCurrentUserContext()`, gewrapt
  in React's `cache()`, dedupliceert deze query binnen één render-pass. Layout en pagina
  delen nu dezelfde query i.p.v. 'm dubbel te doen. Middleware blijft noodgedwongen apart
  (andere runtime/request-fase, niet te delen met de RSC-render).
- **Root cause 2 ("voelt kapot")**: geen enkele visuele feedback bij navigatie totdat de
  volledige nieuwe pagina + data klaar was — dus zelfs bij normale snelheid voelde een tik
  soms "dood" aan.
  Oplossing: `loading.tsx` toegevoegd aan alle hoofdroutes (Next.js toont dit **direct** bij
  navigatie, los van hoe lang de data ophalen duurt) — een simpel skeleton
  (`components/ui/page-loading.tsx`), consistent op elke pagina.
- Blijft bestaand, benoemd als niet dit keer opgelost: Supabase/Vercel cold-starts na een
  periode van inactiviteit (gratis tier) — buiten onze controle, verdwijnt vanzelf bij
  actief gebruik.

**v1.32** — Handleiding toegevoegd + navigatie herbouwd (geen architectuurwijziging):
- **Handleiding** (`/handleiding`): geen rechten-check op lezen (klant-overleg: bewust voor
  iedereen beschikbaar, ook voor de developer als geheugensteun) — wel rolafhankelijk
  gesorteerd: eigen rol-relevante secties staan open bovenaan, de rest staat er ook maar
  dichtgeklapt, zodat niemand hoeft te zoeken maar ook niets verborgen blijft. Bevat 7
  functionele secties + een rollen/rechten-overzichtstabel die direct de `PERMISSIONS`-matrix
  uit `role-helpers.ts` weergeeft (geen dubbele bron van waarheid).
- **Navigatie herbouwd** als horizontale scrollbare pill-knoppenbalk (`overflow-x-auto`,
  snap-scroll) — de tekstlink-rij paste niet meer prettig op één regel nu er 6+ items zijn.
  Handleiding-link zit in dezelfde balk (altijd zichtbaar), geen apart icoon.

**v1.31** — Definitieve rechtenmatrix + volledige migratie van alle bestaande routes (klant-goedgekeurd, grote refactor, geen architectuurwijziging — wel de beloofde eenmalige investering):
- **Rechtenmatrix vastgelegd** in `role-helpers.ts` als single source of truth (zie tabel
  in de code-comment aldaar): 11 permissies (`VIEW_DASHBOARD`, `VIEW_REVENUE`,
  `MANAGE_COMPANIES`, `MANAGE_OPEN_TABS`, `MANAGE_RECEIPTS`, `APPROVE_RECEIPTS`,
  `MANAGE_INVOICES`, `VIEW_DAILY_CLOSING`, `EXECUTE_DAILY_CLOSING`, `MANAGE_TEAM`,
  `MANAGE_SETTINGS`) i.p.v. losse rolchecks — nieuwe rollen toevoegen vereist alleen een
  kolom in de matrix, geen codewijziging elders
- **Alle bestaande API-routes gemigreerd** naar `requireRole()`: companies (+ sub-entiteiten:
  departments/cost-centers/projects/codes — GET blijft open voor dropdown-gebruik door
  Bediening, alleen POST/PUT beveiligd), workflow-rule + required-fields + approval-settings
  (→ `MANAGE_SETTINGS`, was eerder ten onrechte `MANAGE_COMPANIES`), open-tabs, receipts,
  request-approval, generate-invoice, invoices/pdf-url, daily-closing
- **Alle server-component pagina's gemigreerd**: dashboard, companies (+ detail), open-tabs
  (lijst/nieuw/detail — met conditionele facturatie-knoppen op basis van `MANAGE_INVOICES`),
  invoices
- **Navigatie is nu rolbewust** (`layout.tsx`): toont alleen links waar de ingelogde rol
  daadwerkelijk toegang toe heeft — voorkomt dode links naar foutmeldingen
- **Root-redirect rolbewust gemaakt**: `/` stuurde altijd naar `/dashboard`, wat Bediening/
  Keuken niet mogen zien — landt nu op de eerste toegankelijke pagina volgens de matrix
  (Dashboard-rechten → dashboard, anders open-tabs-rechten → rekeningen). Middleware en
  login-scherm stonden nog hardcoded op `/companies` als post-login-bestemming; hersteld
  naar `/` zodat de rolbewuste logica bepaalt waar iemand landt.
- **Tussenoplossing vermeden**: bij het beveiligen van `generate-invoice` bleek een sloppy
  shim nodig geweest te zijn (nep `profile`/`userData`-objecten) om de rest van een groot
  bestand niet te hoeven herzien — dit is expliciet **niet** geaccepteerd (klant-instructie:
  geen tijdelijke hacks) en direct hersteld door alle verwijzingen consequent naar `ctx.*`
  te hernoemen.
- **Bewust nog niet aangepakt**: `companies/new`-formulier (client component) checkt zelf
  geen rol vooraf — de API zelf blokkeert wél (`MANAGE_COMPANIES`), dus geen echt
  beveiligingsgat, alleen een UX-polijstpunt (zou een lege knop tonen die bij versturen een
  foutmelding geeft i.p.v. de knop meteen te verbergen). Genoteerd voor een latere ronde.

**v0.2** — Toegevoegd na review:
- Integration Engine (generiek, i.p.v. Receipt-specifieke sub-engines)
- Workflow Engine (facturatieregels/goedkeuring per bedrijf)
- Notification Engine (event-gedreven, centraal)
- Document Engine (generiek documenttype i.p.v. alleen PDF-facturen)
- Audit & Activity Engine (activity log naast bestaande audit log)
- Receipt Engine opgesplitst in 7 kleine componenten
- Cross-cutting engines nu als skeleton opgenomen vanaf Fase 1 i.p.v. later toegevoegd

**v0.3** — Toegevoegd na tweede review:
- Event Bus als kernlaag (domain events, losse koppeling tussen modules)
- Integration Engine expliciet plugin-gebaseerd (POS/Accounting/Payment/Reservation/Loyalty Plugins)
- Configuratielaag (`configurations`-tabel) i.p.v. maatwerkcode voor bedrijfsregels
- API-first als expliciet ontwerpprincipe (sectie 1)
- Monitoring & Observability als nieuwe cross-cutting module, vanaf Fase 1

**v1.0 — BEVROREN** — Toegevoegd na derde review, laatste ronde vóór implementatie:
- Governance-principes vastgelegd (Event Bus-contracten, database als bron van waarheid, plugin-versiebeheer)
- Niet-functionele vereisten toegevoegd: back-up/herstel, beveiliging (2FA, encryptie, rate limiting)
- Status: GEEN verdere architectuurwijzigingen vóór Fase 1 opgeleverd is

**v1.1** — Implementatie-update (geen architectuurwijziging, alleen voortgang):
- Auth-flow gebouwd: login, middleware-bescherming, uitloggen, wachtwoord-vergeten
- Live omgeving opgezet: GitHub (`stuctech-eng/polder`) → Vercel → Supabase, volledig gekoppeld
- Bedrijvenbeheer: eerste module deels werkend (API + overzicht, aanmaken nog niet)
- **Openstaand besluit:** Resend als SMTP-provider koppelen (i.p.v. Supabase's ingebouwde mail) —
  nodig voor betrouwbare wachtwoord-reset én later voor Facturatie/Notification Engine.
  Overweging Resend vs. Google-inlog: Resend lost het e-mailprobleem op én is sowieso vereist
  voor het versturen van facturen (sectie "Facturatie"); Google-inlog lost alleen het inloggen op
  en vervangt de noodzaak voor een e-mailprovider niet. Gepland voor eerstvolgende sessie.

**v1.2** — Email Engine toegevoegd (architectuurwijziging):
- Notification Engine uitgebreid met Email Provider Interface + Resend als standaardimplementatie
- Governance-principe 6.4: e-mailprovider-onafhankelijkheid (zelfde patroon als kassa-onafhankelijkheid)
- Per-restaurant e-mailinstellingen (afzender, reply-to, eigen domein) — `email_settings`-tabel
- Ondersteunt vanaf nu: facturen, creditfacturen, offertes, betalingsherinneringen,
  wachtwoord-reset, gebruikersuitnodigingen, PDF-bijlagen, HTML/React Email templates,
  webhooks, delivery tracking, bounce handling, SPF/DKIM/DMARC
- Directe aanleiding: onbetrouwbare mailbezorging via Supabase's ingebouwde e-mail (zie v1.1)

**v1.3** — Implementatie-update: Resend gekoppeld en gediagnosticeerd (geen architectuurwijziging):
- Resend SMTP gekoppeld aan Supabase Authentication (host/port/username/API key ingesteld)
- Volledige diagnose van mailbezorgingsprobleem uit v1.1: bevestigd dat Supabase + Resend
  technisch correct samenwerken (test geslaagd naar eigen Resend-accountadres)
- Resterende beperking: Resend-testmodus (`onboarding@resend.dev`) verstuurt alleen naar het
  eigen accountadres — een geverifieerd eigen domein is nodig voor verzending naar klanten/
  personeel/Ziggo-achtige adressen. Zie README voor de handmatige SQL-noodprocedure zolang
  dat domein er nog niet is.

**v1.4** — Bugfix: RLS-policy-lacune (geen architectuurwijziging, kritieke implementatiefout):
- Oorzaak: "Enable automatic RLS" (aangezet bij projectaanmaak, sectie 7.2-aanbeveling) schakelde
  RLS in op **alle** tabellen bij aanmaak — inclusief `users`, waarvoor geen policy bestond.
  Omdat de tenant-isolatiepolicy van andere tabellen intern `users` raadpleegt om de eigen
  `restaurant_id` op te zoeken, faalde die lookup altijd → de app zag nergens data, terwijl
  de SQL Editor (buiten RLS om) alles gewoon toonde. Verwarrend te diagnosticeren omdat
  "succesvolle" SQL-inserts de indruk gaven dat alles werkte.
- Oplossing: `supabase/migrations/0003_fix_rls_policies.sql` — voegt de ontbrekende
  self-select policy op `users` toe, en legt consistente tenant-isolatie vast op alle
  tabellen (rechtstreeks via `restaurant_id`, of via `company_id` → `companies.restaurant_id`
  voor afdelingen/kostenplaatsen/projecten/contactpersonen).
- Les voor vervolg: elke nieuwe tabel moet vanaf nu **in dezelfde migratie** een expliciete
  policy krijgen — automatic RLS beschermt tegen "vergeten RLS aan te zetten", maar niet
  tegen "vergeten een policy te schrijven".

**v1.5** — Bugfix: GRANT-rechten ontbraken (geen architectuurwijziging):
- Tweede, onderliggende laag van hetzelfde symptoom als v1.4: na het herstellen van RLS
  bleef `42501: permission denied for table companies` optreden.
- Oorzaak: "Automatically expose new tables" stond bewust uit (sectie 7.2 beveiliging),
  wat naast het voorkomen van ongewenste API-blootstelling ook de standaard GRANT-rechten
  voor de `authenticated`-rol blokkeerde. RLS bepaalt *welke rijen* zichtbaar zijn; GRANT
  bepaalt *of* een rol de tabel mag benaderen — twee aparte lagen, allebei nodig.
- Oplossing: `supabase/migrations/0004_fix_grants.sql` — expliciete GRANT + `alter default
  privileges` zodat toekomstige tabellen dit automatisch meekrijgen.
- Diagnosemethode die dit oploste: een tijdelijk debug-paneel direct in de UI (user_id,
  query_error, rows) — sectie 15 se debugfilosofie ("fouten moeten zichtbaar zijn in de
  app zelf") bleek doorslaggevend; eerdere aannames over de oorzaak (RLS alleen) waren
  onvolledig zonder deze zichtbare foutcode.
- Les voor vervolg: bij elke nieuwe tabel voortaan **zowel** RLS-policy **als** GRANT
  in dezelfde migratie vastleggen — niet vertrouwen op projectbrede instellingen.

**v1.6** — Implementatie-update + nieuw UX-principe (geen architectuurwijziging aan modules):
- Contextueel uitlegblok toegevoegd op de bedrijfsdetailpagina (Afdeling/Kostenplaats/Project
  in relatie tot de aankomende Open Rekeningen-module)
- Nieuw vast principe 7.3: contextuele in-app uitleg wordt voortaan bij elke module toegevoegd
  waar nodig, en verplicht bijgewerkt zodra de onderliggende logica verandert

**v1.7** — Implementatie-update: Open Rekeningen module (geen architectuurwijziging):
- Volledige flow: rekening openen (bedrijf + optioneel afdeling/kostenplaats/project,
  tafelnummer, aantal personen), overzicht van open rekeningen, detailpagina, sluiten
- Event Bus in gebruik: publiceert `TabOpened` bij aanmaken en `TabClosed` bij sluiten
  (conform het diagram uit sectie 2 — eerste module die daadwerkelijk events publiceert)
- Activity Log: acties gelogd ("opende een nieuwe rekening", "sloot een rekening")
- Contextuele in-app uitleg toegevoegd (principe 7.3) over de relatie met Bedrijf/Afdeling/
  Kostenplaats/Project
- Navigatie in de header uitgebreid (Bedrijven / Rekeningen)
- Bonnen koppelen aan een open rekening is nog niet gebouwd — volgt bij Receipt Manager

**v1.8** — Implementatie-update: Receipt Manager (geen architectuurwijziging):
- Handmatige boninvoer op een open rekening: dynamische productregels (omschrijving,
  aantal, prijs, BTW-tarief 0/9/21%), automatische subtotaal/BTW/totaal-berekening
  server-side (Receipt Validation — nooit vertrouwen op client-berekening voor opslag)
- Bon direct gekoppeld aan de open rekening (`status: linked`) — Receipt Linking uit
  sectie 2 is voor de handmatige invoerroute triviaal, want de koppeling is er al bij
  aanmaak; wordt relevanter bij Fase 2 (import/API/OCR) waar koppeling een aparte stap is
- Event Bus: publiceert `ReceiptLinked`
- Activity Log: bon-toevoeging gelogd met bedrag
- Nog niet gebouwd: Receipt Scanner/OCR/Import (volgt in Fase 2/3), bon bewerken/verwijderen

**v1.9** — Implementatie-update: statusfilter Open Rekeningen (geen architectuurwijziging):
- Tabbladen Open/Gesloten/Gefactureerd toegevoegd aan het rekeningenoverzicht — voorheen
  verdwenen gesloten rekeningen zonder terugvindbaarheid uit de UI
- Contextuele uitleg (principe 7.3) toegevoegd over het verschil tussen de drie statussen,
  inclusief vooruitverwijzing naar "gefactureerd" (komt bij de Facturatie-module)

**v1.10** — Implementatie-update: duidelijkheid bonformulier (geen architectuurwijziging):
- Zichtbare kolomlabels (Product/Aantal/Prijs/BTW) toegevoegd boven de productregels —
  voorheen alleen onzichtbare aria-labels, verwarrend voor de gebruiker
- Contextuele uitleg (principe 7.3) toegevoegd aan de bonnensectie met een concreet voorbeeld

**v1.11** — Bugfix: komma als decimaalteken werkte niet (geen architectuurwijziging):
- HTML `type="number"` velden accepteren alleen een punt als decimaalteken; een
  Nederlandse gebruiker die "12,50" intikt zag de komma genegeerd worden, met een
  verkeerd/verwarrend resultaat (bijv. "050") als gevolg
- Opgelost door aantal/prijs-velden om te zetten naar tekstvelden met numeriek
  toetsenbord (`inputMode="decimal"`) die zowel komma als punt accepteren en
  intern omzetten naar een geldig getal
- Uitlegtekst bijgewerkt om dit te vermelden

**v1.12** — Bugfix: cursor sprong in prijsveld tijdens typen (geen architectuurwijziging):
- Root cause van v1.11 se fix was onvolledig: de weergave werd afgeleid van het
  numerieke getal (0 → toon leeg veld), waardoor het veld zichzelf leegde zodra de
  waarde tijdens het typen tijdelijk 0 werd (bijv. bij "0,50") — dit veroorzaakte
  de rare cursorsprong en het "0,|0"-effect.
- Structurele oplossing: aantal/prijs worden nu als **losse tekstvelden** bijgehouden
  (`quantityText`, `unitPriceText`), volledig onafhankelijk van de numerieke waarde.
  Omzetting naar een getal (met komma-of-punt-ondersteuning) gebeurt alleen nog vlak
  vóór verzending naar de API, nooit meer tijdens het typen zelf.
- Les: bij elk controlled input dat een getal weergeeft, de weergavestring nooit
  afleiden uit het getal zelf als "0" een geldige tussenstap kan zijn — altijd een
  aparte tekststatus bijhouden.

**v1.13** — Implementatie-update: Workflow Engine basis (geen architectuurwijziging):
- Facturatieregel per bedrijf: frequentie (direct/wekelijks/maandelijks/per project) +
  goedkeuring-vereist-vlag, opgeslagen in `workflow_rules` (config-driven, governance 6.1/6.3)
- UI-sectie op de bedrijfsdetailpagina, met contextuele uitleg (principe 7.3)
- Wordt nog niet gebruikt — Facturatie-module (volgende bouwstap) leest deze regel uit
- Opruiming: een niet-gekoppeld wees-bestand (`app/api/receipts/[id]/route.ts`, bon-bewerken
  functionaliteit zonder UI) werd aangetroffen en verwijderd — dit implementeerde een feature
  die expliciet naar een latere polijstronde is uitgesteld; ongebruikte code in de repo is in
  strijd met sectie 7 ("geen dode code") en zou verwarring kunnen geven over wat al werkt

**v1.14** — Implementatie-update: Facturatie-module (geen architectuurwijziging, grote mijlpaal):
- **Basispad nu compleet**: Bedrijf → Open Rekening → Bon → Factuur, volledig werkend end-to-end
- Factuur genereren: aggregeert alle bonnen op een gesloten rekening, berekent subtotaal/BTW/
  totaal, genereert oplopend factuurnummer (`JAAR-0001`), zet rekening naar status `invoiced`
- Document Engine eerste echte implementatie: PDF-generatie met `pdf-lib` (pure JS, Vercel-
  compatibel), opgeslagen in Supabase Storage bucket `documents` (privé), gedownload via
  tijdelijke signed URL (5 minuten geldig) — niet via publieke links
- Event Bus: publiceert `InvoiceGenerated`
- Facturenoverzicht (`/invoices`) toegevoegd aan navigatie
- Bewuste keuze: bij PDF-opslagfout (bijv. bucket ontbreekt) blokkeert dit de factuur zelf
  niet — factuur + regels staan vast in de database, alleen de PDF ontbreekt dan met een
  zichtbare waarschuwing (sectie 15: fouten zichtbaar, actie niet onnodig laten falen)
- Nog niet gebouwd: factuur mailen (wacht op Resend-domein), factuurstatus bijwerken
  (sent/paid), credit-facturen, bewerken/verwijderen van facturen

**v1.15** — Bugfix: storage-RLS ontbrak voor de documents-bucket (geen architectuurwijziging):
- Zelfde patroon als v1.4/v1.5, nu toegepast op Supabase Storage: `storage.objects` heeft
  een eigen RLS-systeem, los van de publieke tabellen. Bucket aanmaken alleen was niet
  genoeg — PDF-upload faalde met "new row violates row-level security policy"
- Oplossing: `supabase/migrations/0005_storage_policies.sql` — tenant-isolatie op basis
  van de eerste mapnaam in het bestandspad (`{restaurant_id}/invoices/...`), zelfde
  patroon als de databasetabellen
- Les voor vervolg: **elke nieuwe storage bucket** heeft net als elke nieuwe databasetabel
  een expliciete RLS-policy nodig — dit geldt nu ook voor de nog aan te maken `receipts`-
  bucket zodra bonscans/OCR gebouwd wordt (Fase 3)

**v1.16** — Implementatie-update: Dashboard (geen architectuurwijziging) — **FASE 1 COMPLEET**:
- Kerncijfers: open/gesloten rekeningen (met doorklik naar gefilterd overzicht), omzet
  deze maand, totaal aantal facturen, top 5 bedrijven op omzet, recente activiteit
  (laatste 8 Activity Log-regels)
- Dashboard is nu de standaard landingspagina (`/` redirect hierheen i.p.v. naar `/companies`)
- **Mijlpaal:** alle Fase 1-onderdelen uit de oorspronkelijke fasering (sectie 4) zijn nu
  gebouwd en end-to-end getest: Event Bus, Auth/Beheer, Bedrijvenbeheer, Open Rekeningen,
  Receipt Manager (handmatig), Workflow Engine (basis), Facturatie (incl. PDF), Dashboard,
  Audit & Activity Engine. Monitoring bleef beperkt tot foutafhandeling in de UI (sectie 15)
  i.p.v. een aparte monitoring-tool — voldoende voor dit stadium, uit te breiden bij schaal.
- Openstaand vóór Fase 2: polijstronde (bewerken/verwijderen), Resend-domein + factuur-mail,
  factuurstatus/betalingen

**v1.17** — Implementatie-update: polijstronde bewerken/verwijderen (geen architectuurwijziging):
- **Bedrijf**: deactiveren/activeren i.p.v. hard verwijderen — boekhoudprincipe: historische
  facturen mogen nooit een "kapotte" verwijzing krijgen naar een verdwenen bedrijf
- **Open rekening**: tafel/aantal personen bewerkbaar; verwijderen alleen toegestaan bij
  status `open` én geen gekoppelde bonnen (voorkomt verlies van echte gegevens)
- **Bon**: bonnummer bewerkbaar; verwijderen alleen toegestaan zolang de bijbehorende
  rekening nog niet `invoiced` is — zodra gefactureerd, is een bon onveranderlijk
  (Guardian Mode impact-analyse: factuur-integriteit/audit trail zou anders corrupt raken)
- Alle wijzig-/verwijderacties loggen naar Activity Log
- **Hiermee is het volledige handmatige basispad (Fase 1 + polijstronde) klaar.**
  Enige resterende afhankelijkheid: e-mailen van facturen wacht op een bewuste
  domeinbeslissing door de restauranthouder (kostenafweging, niet technisch).

**v1.18** — Bugfix: bon toevoegen aan gefactureerde rekening was nog mogelijk (geen architectuurwijziging):
- Gevonden tijdens gebruikerstest: de "+ Bon toevoegen"-knop en de onderliggende API-route
  blokkeerden nog niet op status `invoiced` — alleen bewerken/verwijderen van bestaande
  bonnen was al beschermd (v1.17), maar een geheel **nieuwe** bon toevoegen aan een
  gefactureerde rekening kon nog gewoon, wat de al gegenereerde factuur alsnog inconsistent
  had kunnen maken met de werkelijke rekening.
- Oplossing: check op zowel UI-niveau (knop/formulier verborgen) als API-niveau (server-side
  afgedwongen, niet alleen client-side) — les uit eerdere rondes: UI verbergen alleen is nooit
  voldoende, de daadwerkelijke bescherming moet in de API zitten.

**v1.19** — Bugfix: systematische controle op ontbrekende server-side bescherming (geen architectuurwijziging):
- Naar aanleiding van v1.18 is elke route systematisch nagelopen op hetzelfde patroon
  (UI verbergt actie, API blokkeert niet). Twee extra gaten gevonden en gedicht:
  - **Open rekening bewerken** (tafel/aantal): API accepteerde dit nog op een
    gefactureerde rekening — nu geblokkeerd
  - **Bon bewerken** (bonnummer): zelfde gat als bij verwijderen (v1.17), maar dan voor
    bewerken — nu ook geblokkeerd
- **Extra verharding**: het `status`-veld op de open-rekening-PATCH-route accepteerde
  voorheen elke waarde (`open`/`closed`/`invoiced`), waardoor in theorie een gefactureerde
  rekening handmatig teruggezet had kunnen worden naar `open` — dit had een dubbele
  factuur-generatie mogelijk gemaakt. Nu beperkt tot alleen `closed` (de enige geldige
  gebruikersaangestuurde overgang); `invoiced` gebeurt uitsluitend via de aparte
  generate-invoice-route.
- Vaste werkwijze vanaf nu: bij elke nieuwe "verbergen in UI zodra X"-regel wordt in
  dezelfde wijziging ook de bijbehorende API-route gecontroleerd en zo nodig beveiligd.

**v1.20** — Bugfix: tenant-isolatie niet overal afgedwongen (geen architectuurwijziging, belangrijk vóór multi-restaurant):
- Bredere controle dan v1.18/v1.19: niet "UI verbergt, API blokkeert niet", maar een
  subtielere klasse — routes die zelf `restaurant_id` zetten op basis van de eigen sessie,
  zonder te verifiëren dat een *gekoppelde parent* (bedrijf, rekening) ook echt bij dat
  restaurant hoort. RLS beschermt hier niet automatisch, want de policy op de child-tabel
  checkt alleen zijn eigen `restaurant_id`-kolom, niet de relatie naar de parent.
- **Open rekening aanmaken**: `companyId`/`departmentId`/`costCenterId`/`projectId` worden nu
  geverifieerd — moeten daadwerkelijk bij het eigen restaurant (en bij elkaar, dept/kostenpl./
  project moeten bij het gekozen bedrijf horen) horen, anders expliciete foutmelding
- **Workflow-regel instellen**: bedrijf wordt nu geverifieerd vóór het aanmaken/bijwerken
  van de regel
- **Bon toevoegen**: expliciete "bestaat de rekening?"-check toegevoegd — voorheen kon een
  RLS-gefilterde lege select (tab hoort bij ander restaurant) stilzwijgend doorvallen naar
  "dus niet gefactureerd, dus toestaan"
- Onderliggend patroon (voor toekomstige routes): als een route `restaurant_id` zelf zet
  i.p.v. afleidt van een gekoppelde rij, moet die gekoppelde rij **altijd expliciet
  geverifieerd** worden — RLS "for all"-policies passen hun USING-voorwaarde automatisch
  toe als WITH CHECK bij inserts, maar alléén voor kolommen die de policy zelf checkt
  (bijv. companies/departments/cost_centers/projects zijn hierdoor al veilig; open_tabs,
  receipts en workflow_rules waren dat niet, want hun policy checkt alleen de eigen
  `restaurant_id`, niet de relatie naar companies)

**v1.21** — Architectuuruitbreiding: Approval Engine + Bedrijfsreferenties (klant-goedgekeurd):
- Zie sectie 8 voor volledige specificatie. Generieke `company_codes`-tabel, config-driven
  verplichte velden (hergebruikt bestaande `configurations`-tabel), Approval Engine met
  5 uitwisselbare providers (PIN/E-mail/QR/Handtekening/Restaurant-bevestigt), uitgebreide
  statusworkflow voor bonnen (`locked`-mechanisme, zelfde patroon als gefactureerde
  rekeningen v1.17-v1.20)
- Additief ontworpen: bestaand Fase 1-gedrag (handmatige boninvoer) blijft ongewijzigd
  voor bedrijven zonder Approval-configuratie
- Fasering A-D vastgelegd; **Fase B (welke provider eerst) wacht op klantkeuze**

**v1.22** — Fase B geplant (nog niet geïmplementeerd): volledig implementatieplan vastgelegd
in sectie 10.7 — codebase-review, vertical slice-aanpak, nieuwe/gewijzigde bestanden, risico's.
Bouwvolgorde per klant-instructie: migraties → interfaces → service → providers → routes →
UI → lock-enforcement → events → audit → end-to-end test.

## 11. STATUS

**Architectuur: BEVROREN — v1.0** (kernblueprint) + **v1.21 goedgekeurde uitbreiding** (Approval Engine + Bedrijfsreferenties, sectie 8) + **Daily Closing Engine** (sectie 9). **Implementatie: Fase 1 COMPLEET, Fase A COMPLEET, Fase A.5 (Teambeheer) COMPLEET, Fase B COMPLEET, Fase C (E-mail + QR-goedkeuring) COMPLEET, Daily Closing Engine COMPLEET, definitieve rechtenmatrix + volledige route-migratie COMPLEET (v1.34).** Volgende stap: Fase D (digitale handtekening — nodig voor externe/klant-goedkeuring), niet urgent. Dit document staat per sectie 3 boven aannames.

**Voor een nieuwe sessie/instantie:** begin bij `README.md` sectie "🚦 Start hier" — die bevat de volledige overdracht (huidige stand, eerstvolgende actie, aangehouden werkwijze, bekende valkuilen).
 
