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

**Vervolgfase (na Integration Engine, klant-overleg v1.45): Volledige restaurant-dagafsluiting.**
Belangrijk onderscheid: de bovenstaande gaten zijn **niet** een onvolledige Dagafsluiting —
de module zelf is compleet voor wat er intern beschikbaar is. Ze wachten op een externe
bron (kassa-koppeling) die simpelweg nog niet aangesloten is. Zodra Integration Engine
(Fase 2) er is, breidt Dagafsluiting uit met:
- Kassa-omzet ophalen en **vergelijken** met wat Polder zelf heeft verwerkt (kasverschillen
  direct zichtbaar, bijv. "Kassa €5.240 / Polder €5.180 / Verschil €60 ⚠")
- Pin/contant-splitsing (nu n.v.t., wordt dan wel mogelijk)
- Geannuleerde kassa-transacties + medewerkers/kassahandelingen vergelijken
Volgorde bevestigd: (1) interne administratie ✅ → (2) controle/goedkeuring ✅ →
(3) Integration Engine 🔄 → (4) Dagafsluiting met echte kassacontrole 🔜. Architectuur is
hier al op voorbereid (`daily-closing-service.ts` verzamelt al uit meerdere bronnen —
kassa wordt straks gewoon een extra bron naast de bestaande).

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

## 10. OFFICIËLE ROADMAP (v1.43, klant-goedgekeurd — vervangt oudere losse plannen)

**Uitgangspunt**: kernfunctionaliteit is compleet (Fase 1, A, A.5, B, C, Daily Closing,
rechtenmatrix — allemaal ✅). Wat resteert is uitbreiding en verfijning, geen basis meer
afmaken. Volgorde hieronder is de enige geldende — bij twijfel over prioriteit, dit
raadplegen vóór een oudere sectie.

**Grote lijn — drie architectuurfasen na de huidige kern:**

| Fase | Naam | Inhoud |
|---|---|---|
| 1 | Administratieplatform | ✅ Compleet — Receipt Manager, Workflow Engine, Approval Engine, Teambeheer, Facturatie, Dashboard, Daily Closing, Audit |
| 2 | Integratieplatform | POS-koppelingen, CSV/Excel-import, OCR, QR-scanner |
| 3 | Financieel platform | Payment Provider Interface (Mollie/Stripe), betaallinks, webhooks, automatische betalingsregistratie |

Bewuste scheiding: Fase 1 **beheert** de administratie (bonnen, rekeningen, goedkeuringen,
facturen). Fase 3 gaat een stap verder en **initieert/verwerkt** daadwerkelijke betalingen —
een andere verantwoordelijkheid, met eigen compliance-overwegingen (PSD2) en een externe
afhankelijkheid (Mollie/Stripe-account + transactiekosten), vergelijkbaar met de
Resend-domeinbeslissing. Bewust ná Fase 2 gepland, niet ervoor — eerst het
administratieplatform verder bewijzen.

**1. Factuurstatus + Betalingen** ✅ **COMPLEET (v1.42)**
Statusketen `draft → sent → paid` (+ `overdue`), betalingen met automatische 'paid'-detectie,
Dashboard toont openstaand bedrag. Geen nieuwe migratie nodig — schema bestond al.
**Belangrijk, expliciet vastgelegd**: deze statusketen is en blijft **volledig onafhankelijk**
van de toekomstige Payment Engine (punt 6) — handmatig registreren blijft altijd mogelijk,
ook nadat Mollie/Stripe er ooit bij komt. De Payment Engine zal straks dezelfde status
automatisch bijwerken via een webhook, in plaats van een nieuw, parallel statussysteem te
introduceren.

**2. Resend-domein activeren + facturen mailen** ← eerstvolgende bouwstap
Geen ontwikkelrisico — architectuur (Email Engine, governance 6.4) staat al klaar. Wacht
puur op de domeinbeslissing bij de restauranthouder + configuratie.

**3. Digitale handtekening (Fase D)**
Laatste Approval Provider — maakt de Approval Engine compleet (PIN/Restaurant/E-mail/QR
zijn al ✅).

**4. Integration Engine (Fase 2)**
POS API, CSV/Excel-import, OCR, QR-scanner voor bonnen. Volledig nieuwe ontwikkelfase,
bewust pas ná de bovenstaande punten — eerst de bestaande basis verder laten bewijzen.

> **Research note — Integration Engine** *(nog niet gebouwd, ter voorbereiding; research only)*

> Status: Voorbereiding — nog niet gebouwd
> Datum: 2026-10-03
>
> De applicatie is voorbereid op toekomstige koppelingen met externe POS- en boekhoudsystemen.
>
> De bestaande integration_plugins-tabel is hiervoor al aanwezig. Het beoogde architectuurpatroon volgt dezelfde provider/interface-benadering die eerder is toegepast bij onder andere Approval Providers en Email Providers.
>
> Architectuurrichting
>
> POS-systemen en boekhoudsystemen worden bewust als verschillende integratierichtingen behandeld:
>
> * POSProvider — inbound: ontvangt verkoop-/bongegevens vanuit een kassasysteem.
> * AccountingProvider — outbound: verstuurt bijvoorbeeld factuurgegevens naar een boekhoudsysteem.
>
> Er wordt dus niet één generieke IntegrationProvider gebruikt voor beide richtingen.
>
> De kernlogica van de applicatie moet onafhankelijk blijven van de leverancier:
>
> POS → Sale/Receipt → bedrijf → afdeling → project → factuur → Accounting
>
> De specifieke POS-connector vertaalt het leveranciersspecifieke API-formaat naar een intern genormaliseerd Sale/Receipt-model. De rest van de applicatie werkt uitsluitend met dit interne model.
>
> Beoogde POS-connectors zijn onder andere:
>
> * Eijsink / DISH POS
> * BishPOS
> * toekomstige POS-systemen
>
> Beoogde accounting-connectors zijn onder andere:
>
> * SnelStart
> * toekomstige boekhoudsystemen
>
> Nog te onderzoeken vóór implementatie
>
> Per leverancier moet eerst de officiële API/documentatie worden onderzocht en vastgelegd:
>
> * authenticatiemethode
> * beschikbare endpoints
> * OAuth/API-key/credentials
> * beschikbare verkoopgegevens
> * bonnummer
> * datum/tijd
> * tafel
> * productregels
> * bedragen
> * BTW
> * betaalstatus
> * vestiging/locatie
> * externe referenties
> * webhooks/event-notificaties
> * rate limits
> * historische gegevens
> * foutafhandeling
> * sandbox/testomgeving
> * voorwaarden voor externe integraties
>
> Pas nadat deze research is uitgevoerd, kan worden bepaald welke concrete provider-contracten en datamodellen noodzakelijk zijn.
>
> Architectuurbeslissing: de Integration Engine wordt provider-gebaseerd ontworpen, zodat een POS-wissel alleen de betreffende connector raakt en niet de kern van de applicatie.
>
> Harde status: research only. Geen implementatie gestart.

**Eerste onderzoeksresultaten (2026-10-08, desk research, nog niets gebouwd)**
- **SnelStart (AccountingProvider)**: B2B API v2 (`https://b2bapi.snelstart.nl/v2`), géén OAuth.
  Nodig: subscription key (Developer Portal) + koppelsleutel van de klant (Koppelingen >
  Maatwerk in SnelStart) → access token (verloopt na 1 uur). Resources o.a. Verkoopboekingen en
  Facturen. Productiegebruik vereist certificatie (±12 dagen monitoring) en
  partnerstatus; eenmalig €250 ex. BTW per productiesleutel. Klant heeft inZicht of inControle
  nodig. Geen echte sandbox, wel ontwikkel-/testsleutel. Rate limits: nog onbekend.
- **Eijsink / DISH POS (POSProvider)**: geen openbare API-documentatie gevonden. DISH nam
  Eijsink over in 2022. Vervolg: contact met DISH opnemen (partnerprogramma / API-toegang /
  webhooks) — waarschijnlijk afhankelijk van hun goedkeuring.
- **BishPOS (POSProvider)**: niets bruikbaars gevonden; leverancier rechtstreeks benaderen.
- **Open actie (Te, later)**: vaststellen welke kassa het restaurant gebruikt en de leverancier
  benaderen over API-toegang/partnerprogramma. Pas daarna Integration Engine verder uitwerken.
- **Conclusie**: de boekhoudkant (SnelStart) is goed gedocumenteerd; de POS-kant hangt van
  leverancierscontact af. Eerst vaststellen welke kassa het restaurant echt gebruikt.

**5. Kleine verfijningen** — pas oppakken bij concrete behoefte, niet uit zichzelf plannen:
- **Facturatie: automatische vervaldatumcontrole ("te laat"-indicatie)** — klant-overleg:
  géén nieuwe factuurstatussen toevoegen ("Openstaand"/"Afgesloten" zijn al af te leiden uit
  bestaande data: verzonden + niet volledig betaald = openstaand). Wél interessant:
  automatisch tonen dat een factuur te laat is, **berekend bij het weergeven**
  (`vandaag > vervaldatum && betaald < totaal`), nooit als los database-veld dat een
  achtergrondtaak moet bijwerken — zelfde principe als elders in Te's projecten
  (bijv. `kasSaldo` altijd berekend, nooit opgeslagen). Kwaliteitsverbetering op een al
  werkend systeem, geen ontbrekende kernfunctie — bewust laag geprioriteerd, onder
  Integration Engine.
- QR/e-mail-goedkeuringslinks: tijdgebonden vervaldatum + handmatig intrekken (statuscontrole
  zelf — link werkt alleen bij `pending`, geweigerd na approved/rejected — bestaat al sinds
  Fase C, dit zijn dus verfijningen bovenop een werkend fundament, geen ontbrekende kern)
- Dagafsluiting heropenen
- Contante/pin-omzetsplitsing
- Niet-gekoppelde bonnen-controle (hoort feitelijk bij punt 4)
- Configureerbare rechtenmatrix (database-driven i.p.v. code)

**6. Payment Engine (Fase 3 — financieel platform)** — ná Integration Engine, niet ervoor
Zelfde architectuurpatroon als Approval Engine/Email Engine: een **Payment Provider
Interface** die de Factuurmodule als enige aanspreekpunt kent ("maak een betaalverzoek"),
met Mollie als eerste implementatie (Stripe optioneel later).

```
Payment Engine
      │
Payment Provider Interface
      │
──────────────────────────
│                        │
Mollie Provider    Stripe Provider
```

Events, zelfde patroon als de rest (Event Bus, governance 6.1):
`InvoiceCreated → PaymentRequested → PaymentPending → PaymentSucceeded → InvoicePaid`
(of `PaymentFailed`/`PaymentExpired` als alternatieve uitkomst).

Omvat: betaallinks versturen (via de bestaande Email Engine), webhooks ontvangen en
verwerken, automatische betalingsregistratie (schrijft naar dezelfde `payments`-tabel als
punt 1 — geen apart, parallel systeem), betalingshistorie, optioneel herinneringen.

**7. Platformbeheer (control plane) en privacyfase** — *nog niet gebouwd; eerst architectuuraudit/plan, daarna bouwen* (advies GPT, door Claude overgenomen, 2026-10-08)
- **Twee lagen, geen extra rol**: platformbeheer staat los van de restaurantrollen. Aparte tabel
  `platform_admins (user_id, active, created_at)`, alleen in de database te vullen, nooit via
  de app. Geen gedeeld admin-account: elke beheerder een eigen identiteit.
- **Geen RLS-uitzondering "platformbeheerder mag alles"**: `restaurant_id` + RLS blijft de
  primaire grens voor alle restaurantdata. Beheeracties lopen via gecontroleerde
  server-side routes (service-role, nooit in de browser).
- **Beheerscherm**: restaurant aanmaken, eerste eigenaar uitnodigen, restaurant aan/uit zetten,
  overzicht. Platformdata (naam, status, eigenaar, abonnement, integratiestatus) is iets anders
  dan restaurantdata (bonnen, omzet, facturen, bedragen).
- **Platform-auditlog**: alle beheeracties loggen (restaurant aangemaakt/gedeactiveerd,
  eigenaar uitgenodigd, gebruiker aangemaakt/verwijderd, integratie gekoppeld/ontkoppeld,
  supporttoegang gestart/beëindigd).
- **Fase A — nu/ontwikkeling (test mode)**: platformbeheerder mag alles zien, **alleen met
  testdata**. Expliciet vastgelegd als tijdelijke status zodat dit niet per ongeluk de
  productie-architectuur wordt.
- **Fase B — vóór eerste echte restaurantdata (production mode)**: geen standaardtoegang tot
  restaurantinhoud. Support = bewuste handeling: reden opgeven → restaurant kiezen → tijdelijk
  beperkte toegang → alles loggen → toegang eindigt.
- **Privacyfase vóór het eerste echte restaurant**: privacybeleid, verwerkersovereenkomst,
  verwerkingsregister, subverwerkers (Supabase, Vercel, Resend), bewaartermijnen,
  datalekprocedure, toegangsbeleid. Voorafgaand: security-audit (RLS, tenant-isolatie,
  platform-admin, logging).
- **Stand**: audit (fase 0) is uitgevoerd — zie sectie 13. **Definitieve volgorde** (besluit Te,
  2026-10-08), elke stap vereist een eigen expliciete GO, na elke stap testen, stoppen, her-auditen:
  1. Fase 0 — audit ✅ (sectie 13)
  2. Baseline en reproduceerbaarheid ✅ (migratie 0014, geen gedragswijziging)
  3. **Security hardening** — rollen in de database/RLS afdwingen, gevaarlijke wijzig-/verwijderrechten
     dichtzetten, logboeken append-only, cross-restaurant relaties afdwingen, TRUNCATE/TRIGGER/
     REFERENCES intrekken, `search_path` van `my_restaurant_id()`, profielaanmaak server-side
     — **vóór** platformbeheer en vóór meerdere restaurants
  4. Platformbeheer (`platform_admins`, platformcontext, restaurantstatus)
  5. Restaurantbeheer (aanmaken, eigenaar uitnodigen, actief/inactief, platformlogboek)
  6. Default Restaurant / configuratiemodel (alleen configuratie kopiëren, nooit data)
  7. Restaurant testen (gecontroleerde inzage met reden, tijdslimiet, logging)
  8. UI (platformomgeving en restaurantomgeving, modules op basis van configuratie)
  9. Integraties met veilige secret-opslag
  10. Privacy en productieklaar
  Tot platformbeheer er is maakt Dick restaurants aan met SQL.

## 11. WIJZIGINGSHISTORIE

**v1.60** — Security hardening STAP 7 (H4a): migratie `0021_hardening_step7_tabs_receipts.sql` + rollback (rolbewuste policies en vier vangnet-triggers op `open_tabs`, `receipts`, `receipt_lines`, `approvals`), sectie 13.15. Geen app-wijziging. Lokaal getest; productie wacht op uitvoering.

**v1.59** — Security hardening STAP 6 (H6): migratie `0020_hardening_step6_storage.sql` + rollback, `upsert:false` in `generate-invoice`, sectie 13.14. In productie en akkoord.

**v1.58** — Security hardening STAP 5 (H7): migratie `0019_hardening_step5_crossref.sql` + rollback, sectie 13.13. Productie wacht op uitvoering.

**v1.57** — Security hardening STAP 4 (H5a): migratie `0018_hardening_step4_logs_append_only.sql` + rollback, sectie 13.12. Productie wacht op uitvoering.

**v1.56** — Security hardening STAP 3 (H2): migratie `0017_hardening_step3_users.sql` + rollback, server-side teambeheer (`user-admin-repository`), sectie 13.11. Productie wacht op uitvoering.

**v1.55** — Security hardening STAP 2 (H3 + H8a): migratie `0016_hardening_step2_restaurants_privileges.sql` + rollback.
`restaurants` alleen nog leesbaar (eigen restaurant, actieve gebruiker); TRUNCATE/TRIGGER/REFERENCES weg; anon zonder tabelrechten.
Geen app-code gewijzigd. Sectie 13.10. Stap 3 wacht op nieuwe expliciete GO.

**v1.54** — Security hardening STAP 1 (H1 + H9): migratie `0015_hardening_step1_helpers.sql` + rollback. `my_restaurant_id()` vast
search_path + `is_active` (fail closed), nieuwe `my_role()`, `role_has_permission()`, `has_perm()`, EXECUTE alleen voor authenticated en
service_role. Geen policy-, grant-, trigger-, storage- of app-wijziging. Sectie 13.9. Stap 2 wacht op nieuwe expliciete GO.

**v1.53** — Security hardening STAP 0 (voorbereiding, geen productiewijziging): map `supabase/hardening/`
(alleen-lezen productiecontroles, staging-seed, testharnas + 168 testcases, rechtenbaseline, README met
migratie/rollbackstructuur voor de 11 stappen). Sectie 13.7 beschrijft de uitkomst. Geen migratie, policy,
grant, trigger, functie of app-code gewijzigd. Wacht op nieuwe expliciete GO voor stap 1.

**v1.52** — Documentatie: `docs/security-hardening-plan.md` toegevoegd (alleen plan; geen migratie,
policy-, privilege- of codewijziging). Sectie 13.6 verwijst ernaar.

**v1.51** — Fase 0 afgerond: schema- en securityaudit (sectie 13) + baseline-migratie 0014:
- Nieuwe migratie `0014_baseline_production_state.sql` (zet RLS op `users` aan zoals in productie,
  idempotent, **geen gedragswijziging**) en `supabase/scripts/verify-baseline.sql` (alleen lezen).
- Roadmap-punt 7 bijgewerkt met de definitieve volgorde (hardening vóór platformbeheer).
- Geen app-code gewijzigd, geen UI-wijziging, geen hardening, geen platformbeheer.

**v1.50** — Documentatie: roadmap-punt 7 toegevoegd (platformbeheer/control plane + privacyfase).
Geen code.

**v1.49** — Documentatie: eerste desk research Integration Engine toegevoegd onder roadmap-punt 4
(SnelStart-authenticatie en kosten, DISH/BishPOS: geen openbare API gevonden). Nog steeds geen code.

**v1.48** — Documentatie: research note Integration Engine vastgelegd (geen code, geen implementatie):
- Letterlijk opgenomen onder roadmap-punt 4 (sectie 10), status **research only**.
- Kernbesluit: POSProvider (inbound) en AccountingProvider (outbound) zijn gescheiden
  richtingen; géén generieke IntegrationProvider. Kern blijft leveranciersonafhankelijk via
  een intern Sale/Receipt-model; een POS-wissel raakt alleen de connector.
- Eerst per leverancier (Eijsink/DISH, BishPOS, SnelStart) de officiële API-documentatie
  onderzoeken; pas daarna provider-contracten en datamodellen bepalen.

**v1.47** — Bugfix: keep-alive ping gaf 401 (geen architectuurwijziging):
- **Oorzaak**: het kale `/rest/v1/`-pad (zonder specifieke tabel) accepteert bij dit
  Supabase-project alleen de secret/service-role key, niet de publieke anon-key — gaf
  `"Secret API key required"`.
- **Oplossing**: `app/api/ping-supabase/route.ts` gebruikt nu de service-role key
  (uitsluitend server-side, nooit blootgesteld) en vraagt een concrete, onschuldige tabel
  op (`restaurants?select=id&limit=1`) i.p.v. het kale root-pad — werkt gegarandeerd,
  bypast bovendien meteen elke RLS/GRANT-afhankelijkheid.
- Diagnosemethode nogmaals bevestigd: tijdelijk de exacte Supabase-foutmelding
  meesturen loste dit in één keer op, zelfde patroon als v1.36.

**v1.46** — Supabase keep-alive toegevoegd (geen architectuurwijziging) + sandbox-herstel gedocumenteerd:
- **Aanleiding**: Supabase's gratis tier pauzeert een project automatisch na 7 dagen zonder
  API/database-activiteit — puur inloggen op het dashboard telt niet mee. Gebeurde al
  eenmaal in de praktijk.
- **Oplossing**: `app/api/ping-supabase/route.ts` (lichte, publieke healthcheck-route, geen
  gevoelige data) + `vercel.json` met een dagelijkse Vercel Cron Job — ruim binnen zowel
  Supabase's 7-dagen-drempel als Vercel's gratis-tier-limiet (1×/dag op Hobby-plan). Gekozen
  boven een losse GitHub Action of externe cron-dienst omdat het in dezelfde repo blijft die
  toch al beheerd wordt (geen extra secrets/dienst nodig).
- Route toegevoegd aan de publieke paden in `middleware.ts` — anders zou de cron-aanroep
  zelf al geblokkeerd worden vóórdat 'm Supabase kan bereiken (geen sessie/cookie
  beschikbaar voor een cron-aanroep).
- **Operationele noot, geen architectuurwijziging**: tijdens deze bouwstap bleek de
  sandbox-werkomgeving zelf gereset te zijn (kan gebeuren bij zeer lange sessies) — het
  project is volledig hersteld uit de laatst gedeelde ZIP in de outputmap, geverifieerd met
  een schone `npm install` + TypeScript-check + volledige build (21 routes/pagina's, alles
  intact). Bevestigt de waarde van "altijd de laatste ZIP bevat alles" als werkwijze.

**v1.45** — Daily Closing vervolgfase vastgelegd: volledige restaurant-dagafsluiting na Integration Engine (klant-overleg, geen implementatie — planning only):
- **Belangrijke verduidelijking**: de huidige "n.v.t."-gaten in Daily Closing (contant/pin-
  splitsing, niet-gekoppelde bonnen) zijn géén onvolledigheid van de module zelf — de
  module is compleet voor wat intern beschikbaar is. Ze wachten op een externe bron
  (kassa-koppeling) die pas met Integration Engine (Fase 2) beschikbaar komt.
- Vastgelegd wat Daily Closing dan krijgt: kassa-omzet vergelijken met wat Polder zelf
  verwerkte (directe kasverschil-detectie), pin/contant-splitsing, geannuleerde
  kassa-transacties en medewerkers/kassahandelingen vergelijken.
- Architectuur al voorbereid: `daily-closing-service.ts` verzamelt al uit meerdere interne
  bronnen (governance 6.2, alleen lezen) — kassa wordt straks gewoon een extra bron naast
  de bestaande, geen herontwerp nodig.
- Volgorde herbevestigd: interne administratie ✅ → controle/goedkeuring ✅ →
  Integration Engine 🔄 → Dagafsluiting met kassacontrole 🔜.

**v1.44** — Roadmap-verfijning: automatische "te laat"-detectie toegevoegd, extra factuurstatussen expliciet afgewezen (klant-overleg, geen implementatie — planning only):
- **Bewuste keuze om NIET te bouwen**: voorstel voor 5 factuurstatussen
  (`Concept/Verzonden/Openstaand/Administratief betaald/Afgesloten`) kritisch beoordeeld —
  "Openstaand" en "Afgesloten" voegen geen nieuwe informatie toe (al af te leiden uit
  bestaande `status`+`payments`-data) en zijn bewust niet toegevoegd. Voorkomt een tweede,
  overlappende plek om dezelfde toestand bij te houden.
- **Wel toegevoegd aan roadmap (punt 5, laag geprioriteerd)**: automatische
  vervaldatumcontrole — een factuur toont "te laat" zodra `vandaag > vervaldatum` én nog
  niet volledig betaald, **berekend bij weergave**, nooit als database-veld dat een
  achtergrondtaak zou moeten bijwerken. Zelfde principe als eerder toegepaste patronen
  (bijv. `kasSaldo` altijd berekend, nooit opgeslagen, uit een eerder project van de klant).
- **Payment Engine (Fase 3, v1.43) opnieuw bevestigd**: geen bankkoppeling, geen
  betaalproviders, geen webhooks/PSD2 totdat er een concrete behoefte aan automatische
  betalingen ontstaat — de huidige handmatige registratie houdt het systeem bewust simpel
  en onder controle van de eigenaar.

**v1.43** — Payment Engine (Fase 3) toegevoegd aan de officiële roadmap (klant-overleg, geen implementatie — planning only):
- Vastgelegd als **derde architectuurfase**, ná Fase 2 (Integration Engine): Fase 1
  (Administratieplatform, compleet) → Fase 2 (Integratieplatform) → Fase 3 (Financieel
  platform). Bewuste volgorde: eerst het administratieplatform verder bewijzen, dan pas de
  stap naar daadwerkelijk betalingen initiëren/verwerken — een andere verantwoordelijkheid
  dan administratie beheren, met eigen compliance-overwegingen (PSD2).
- Architectuur vooraf vastgelegd (nog niet gebouwd): Payment Provider Interface, Mollie als
  eerste implementatie, event-keten `InvoiceCreated → PaymentRequested → PaymentPending →
  PaymentSucceeded/Failed/Expired → InvoicePaid`, zelfde patroon als Approval/Email Engine.
- **Expliciete garantie vastgelegd**: de in v1.42 gebouwde factuurstatus/betalingen-flow
  (handmatig registreren) blijft volledig functioneel en onafhankelijk — de Payment Engine
  schrijft later naar dezelfde `payments`-tabel via een webhook, introduceert geen nieuw
  parallel statussysteem. Dit was een expliciete zorg tijdens het overleg en is nu als
  architectuurbeslissing vastgelegd, niet alleen als mondelinge afspraak.

**v1.42** — Factuurstatus + Betalingen geïmplementeerd (roadmap-punt 1, klant-goedgekeurd, geen architectuurwijziging):
- **Statusketen**: `draft → sent → paid` (plus `overdue`, al in het schema sinds Fase 1).
  Handmatig markeren als "verzonden"; "betaald" gebeurt **automatisch** zodra de som van
  betalingen de factuur volledig dekt — geen handmatige stap die vergeten kan worden.
- **Betalingen registreren**: bedrag + optionele methode, meerdere deelbetalingen mogelijk
  per factuur. Toont "€X betaald, nog €Y openstaand" totdat volledig gedekt.
- **Guardian Mode-guard**: een betaalde factuur kan niet handmatig teruggezet worden naar
  een eerdere status via de PATCH-route — voorkomt inconsistentie met de betalingshistorie.
- **Dashboard uitgebreid**: nieuwe kaart "Openstaand (nog te betalen)" — som van
  onbetaald/deels-betaald over alle `sent`/`overdue`-facturen. Dit was expliciet het
  gevraagde doel ("welke facturen staan nog open, wat moet nagebeld worden").
- **Geen nieuwe migratie nodig** — `invoices.status` en de `payments`-tabel bestonden al
  sinds de allereerste Fase 1-migratie (0001), alleen nooit gebruikt. Bevestigt de waarde
  van vroeg een compleet schema neerzetten, ook voor functionaliteit die pas later gebouwd
  wordt.
- Nieuwe bestanden: `app/api/invoices/[id]/route.ts` (PATCH status), `.../payments/route.ts`
  (GET/POST), `invoice-list-item.tsx` (client component, zelfde patroon als `ReceiptItem`).

**v1.41** — Officiële roadmap vastgelegd (sectie 10), klant-goedgekeurd, vervangt oudere
losse plannen/adviezen verspreid door eerdere gesprekken:
- Volgorde: (1) Factuurstatus + Betalingen, (2) Resend-domein + facturen mailen, (3)
  Digitale handtekening (Fase D, laatste Approval Provider), (4) Integration Engine
  (Fase 2), (5) kleine verfijningen — pas bij concrete behoefte
- Correctie tijdens het opstellen: QR/e-mail-goedkeuringslinks worden al automatisch
  ongeldig na `approved`/`rejected` (bestond al sinds Fase C, statuscontrole op
  `pending`) — alleen tijdgebonden vervaldatum en handmatig intrekken ontbreken nog,
  niet de hele beveiliging zoals eerst gesuggereerd
- README's "Nog te bouwen"-lijst tegelijk opgeschoond: twee verouderde regels gevonden
  en gecorrigeerd (Fase B stond nog als "niet geïmplementeerd" terwijl die al v1.28
  compleet was; Handleiding stond nog als "te bouwen" terwijl die al v1.32 bestond) —
  les: periodiek de open-punten-lijst tegen de wijzigingshistorie aanhouden om dit soort
  drift te voorkomen

**v1.40** — Kritieke bugfix: `users`-tabel had nooit UPDATE/DELETE RLS-policies (geen architectuurwijziging):
- **Symptoom**: rol wijzigen op de Team-pagina gaf `"Cannot coerce the result to a single
  JSON object"` — de generieke PostgREST-foutmelding voor een `.single()`-call die 0 rijen
  teruggeeft.
- **Root cause**: sinds `users` bestaat, zijn er alleen SELECT-policies aan toegevoegd
  (v1.4: eigen profiel lezen; v1.24a: teamleden zien binnen hetzelfde restaurant) — nooit
  een UPDATE- of DELETE-policy. Elke poging tot rol wijzigen (`userRepository.updateRole`),
  activeren/deactiveren, of verwijderen deed dus altijd een RLS-geblokkeerde, stilzwijgend
  mislukte database-operatie — dit was de **eerste keer** dat een van deze acties
  daadwerkelijk werd getest, dus de lacune bleef tot nu toe onopgemerkt.
- **Oplossing**: `supabase/migrations/0013_fix_users_update_delete_rls.sql` — expliciete
  UPDATE- en DELETE-policies, tenant-isolatie via `my_restaurant_id()` (zelfde functie als
  v1.24a). De policy zelf is niet rol-specifiek (elke gebruiker binnen het restaurant zou
  technisch een ander teamlid kunnen bewerken op databaseniveau) — dat is bewust, want de
  daadwerkelijke rolcontrole (alleen eigenaar) gebeurt al vóór de database via
  `requireRole("MANAGE_TEAM")` in de API-route, exact hetzelfde patroon als overal elders.
  RLS is hier de tenant-isolatie-vangnet-laag, niet de primaire autorisatielaag.
- **Patroon-herhaling**: dit is de **derde keer** dat een RLS-policy-set onvolledig bleek
  te zijn gebleven totdat een specifieke actie voor het eerst werd getest (v1.4: SELECT
  op users ontbrak voor genest gebruik; v1.36: GRANT voor service_role ontbrak). Les
  bevestigd: **elke nieuwe database-operatie op een tabel moet expliciet getest worden**,
  niet aangenomen "de tabel heeft al RLS, dus het werkt wel" — RLS is per operatie-type
  (SELECT/INSERT/UPDATE/DELETE) een aparte, losse policy, geen alles-in-één-schakelaar.

**v1.39** — Bonweergave verbeterd: eigen regel voor status, afwijzing zichtbaar, bewerkformulier uitgebreid (geen architectuurwijziging, drie gebruikersgevonden punten in één ronde):
- **Leesbaarheid**: "✓ goedgekeurd door [naam]" stond voorheen inline achter het bonnummer,
  nu op een eigen regel eronder — voorkomt afkappen op smalle schermen (zoals zichtbaar was
  bij "Test jopie" die tegen het bedrag aan liep).
- **Afwijzing was onzichtbaar**: een afgewezen bon ging terug naar status `linked` (bewust,
  zodat personeel 'm kan corrigeren) — maar toonde daardoor **geen enkel spoor** meer van de
  afwijzing zelf, zag er identiek uit aan een gewone nieuwe bon. Nu toont de bon
  "⚠ eerder afgewezen door [naam]: '[reden]' — nu weer bewerkbaar" zolang er geen nieuwere
  goedkeuring overheen ligt. Vereiste het apart uit elkaar trekken van `approved_by` vs.
  `rejected_by` in de query (voorheen één ongedifferentieerd "laatste resultaat"-veld).
- **Bewerken deed te weinig**: de API (`PATCH /api/receipts/[id]`) ondersteunde altijd al
  `receiptDate` en `notes` naast `receiptNumber`, maar de UI toonde alleen het bonnummer-veld
  — een sinds de polijstronde (v1.17) blijvende inconsistentie tussen wat de API kon en wat
  de gebruiker kon zien. Bewerkformulier toont nu ook datum en opmerkingen.

**v1.38** — Naam tonen bij goedgekeurde bon (geen architectuurwijziging, afronding v1.37):
- **Gevonden gat**: de naam van wie een bon goedkeurde (v1.37: verplicht veld op de publieke
  pagina, al opgeslagen in `approvals.approved_by`) werd wél vastgelegd, maar nergens getoond
  op de bon zelf — alleen terug te vinden via de Activity Log op het Dashboard.
- **Oplossing**: `open-tabs/[id]/page.tsx` haalt nu ook `approved_by`/`approved_at` op uit de
  `approvals`-embed en bepaalt het meest recente afgeronde resultaat (approved of rejected,
  niet alleen de pending-rij); bonnenlijst toont nu "✓ goedgekeurd door [naam]".
- **Bijkomende consistentiefix**: de **interne** PIN/Restaurant-bevestigt-goedkeuring (via de
  ingelogde `/api/receipts/[id]/approve`-route) gaf de naam ook niet direct terug aan de UI —
  nu wel, zodat de naam meteen zichtbaar is zonder page-refresh, consistent met de externe
  e-mail/QR-flow.
- **Patroon herhaald uit v1.35**: ook hier gold "iets wat eenmalig in een API-response
  terugkomt, moet ook herleidbaar zijn uit de database-query van de pagina zelf" — ditmaal
  vooraf goed toegepast in plaats van achteraf ontdekt als bug.

**v1.37** — Naamregistratie + afwijzen toegevoegd aan publieke goedkeuring (geen architectuurwijziging):
- **Naam verplicht**: wie de publieke `/approve/[token]`-link opent (klant of manager op
  afstand) moet nu een naam invullen vóór goedkeuren/afwijzen — vastgelegd in
  `approvals.approved_by`, i.p.v. het generieke "extern (via link)" van v1.34.
- **Afwijzen toegevoegd**: eerste echte reject-flow in de Approval Engine. Bon gaat terug
  naar `linked` (opnieuw bewerkbaar door personeel), `approvals.status = rejected` met
  optionele reden in `metadata` (jsonb, bestond al sinds Fase B). Nieuw event:
  `ApprovalRejected`.
- **Daily Closing Engine bijgewerkt**: de controle "Afgekeurde bonnen" toonde sinds de
  eerste versie bewust "n.v.t." (afkeuren bestond nog niet) — nu een echte, werkende
  telling van vandaag afgewezen bonnen. Mooi voorbeeld van hoe een eerlijk benoemd gat
  later alsnog gesloten wordt zodra de onderliggende functionaliteit er is.
- **Aanleiding**: directe vervolgvraag op de succesvolle Fase C-test ("de bedoeling is dat
  de klant zelf scant, toch?") — bevestigde dat dit zonder naamregistratie een zwakke
  audit trail zou geven voor een externe partij, en dat "alleen goedkeuren, nooit afwijzen
  kunnen" een onnodige beperking was.

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

## 13. FASE 0 — SCHEMA- EN SECURITYAUDIT (2026-10-08)

*Alleen gelezen en geanalyseerd (repo + live Supabase via pg_class, pg_policies, information_schema,
pg_proc, auth.users). Niets aangepast in productie.*

### 13.1 Conclusie
- **Tussen restaurants is geen lek gevonden.** RLS staat op alle 25 tabellen in `public` aan en elke
  policy begrenst op restaurant. De rol `anon` heeft geen SELECT/INSERT/UPDATE/DELETE op enige tabel.
- **Binnen één restaurant is de database te ruim**: rolrechten worden alleen in de app afgedwongen,
  niet in de database.
- **De repo was niet de waarheid**: productie wijkt op twee punten af (13.3). Productie is het
  uitgangspunt; de repo is daarmee in overeenstemming gebracht (migratie 0014).

### 13.2 Bevestigde bevindingen (productie)
| # | Bevinding | Ernst | Oplossen in |
|---|---|---|---|
| 1 | Elke teamgenoot kan zichzelf/anderen een andere rol geven, ook `owner` (UPDATE-policy op `users` kijkt niet naar rol; `restaurant_id` kan niet wijzigen) | Hoog | Hardening |
| 2 | Elke teamgenoot kan collega's, ook de eigenaar, verwijderen (DELETE-policy op `users`) | Hoog | Hardening |
| 3 | Elke teamgenoot kan het eigen restaurant wijzigen/verwijderen (`restaurants`: ALL; cascade wist alle data) | Hoog | Hardening |
| 4 | `audit_log`, `activity_log`, `domain_events` zijn door teamleden te wijzigen/wissen | Hoog | Hardening |
| 5 | Vergrendelen, goedkeuren, factuurstatus, betalingen en dagafsluiting alleen in de app afgedwongen; via directe API te omzeilen | Hoog | Hardening |
| 6 | Opslag (`documents`-bucket): elke teamgenoot kan documenten/factuur-PDF's van het eigen restaurant overschrijven (UPDATE); verwijderen kan niet (geen DELETE-policy) | Middel | Hardening |
| 7 | `integration_plugins`: voor elke rol leesbaar/schrijfbaar, `config` is platte JSON | Middel (nog geen sleutels) | Vóór integraties |
| 8 | Kindrijen kunnen naar rijen van een ander restaurant verwijzen (alleen eigen `restaurant_id` wordt gecontroleerd; integriteit, geen leesrisico) | Laag-middel | Hardening |
| 9 | `anon` en `authenticated` hebben TRUNCATE, TRIGGER, REFERENCES op alle tabellen (PostgREST biedt TRUNCATE vermoedelijk niet aan; onnodig breed) | Laag | Hardening |
| 10 | `my_restaurant_id()` is SECURITY DEFINER zonder vast `search_path` | Laag | Hardening |

### 13.3 Verschillen repo ↔ productie (opgelost in migratie 0014)
1. **RLS op `users`** stond in productie aan (handmatig), maar in geen enkele migratie. Een omgeving
   opgebouwd uit uitsluitend de migraties kreeg `users` dus zonder RLS (de vier policies bestonden
   wel, maar doen zonder RLS niets). Aangetoond met een lege Postgres: na 0001–0013 stond RLS op
   `users` uit.
2. **`email_settings`** (migratie 0002) staat niet in productie en wordt in de code niet gebruikt.
   Bewust **niet** aan productie toegevoegd zonder functionele reden; 0002 blijft ongewijzigd in de
   repo. Gevolg: een verse omgeving heeft 26 tabellen, productie 25 (alleen deze ene tabel verschilt).
3. Overige tabellen, policies, `my_restaurant_id()` en opslag-policies komen overeen.
4. **Rechten (GRANT)**: productie heeft naast de repo-grants (0004, 0012) ook de platformstandaard
   (`anon`/`authenticated`: REFERENCES, TRIGGER, TRUNCATE). Die komen van Supabase, niet uit de repo,
   en worden pas in de hardening ingetrokken.

### 13.4 Nog onbewezen
Uitnodigen schrijft het profiel via de gewone gebruikersverbinding in `users`, en voor `users`
bestaat **geen INSERT-policy** (bewust niet toegevoegd; ook niet in 0014). Het kan dus zijn dat een
uitnodiging wel het Auth-account aanmaakt en de mail verstuurt, maar het profiel niet opslaat.
Dit is nooit echt getest (de Resend-testlimiet stopte eerdere pogingen vóór de profielstap). Er is
precies één account zonder profiel (`stuctech@gmail.com`, 2026-07-05, van vóór het teambeheer):
geen bewijs voor het probleem, wel een los eind (opruimen/koppelen in de hardening).
**Besluit**: profielaanmaak gebeurt gecontroleerd server-side (service-role, ná de rechtencontrole
`MANAGE_TEAM`), **niet** via een algemene INSERT-policy op `users`.

### 13.5 Baseline (stap 1, migratie 0014)
- `supabase/migrations/0014_baseline_production_state.sql`: zet RLS op `users` aan, herhaalt
  `my_restaurant_id()` identiek, en maakt de vier `users`-policies alleen aan als ze ontbreken.
  **Idempotent, geen gedragswijziging, geen hardening.** In productie een no-op; draaien is niet
  nodig (mag wel).
- `supabase/scripts/verify-baseline.sql`: alleen-lezen controle (RLS overal aan, vier `users`-policies,
  `my_restaurant_id`, policy-aantallen) om productie of een nieuwe omgeving te toetsen.
- **Getest op een lege lokale Postgres 16** (stubs voor `auth`/`storage`): (a) verse omgeving,
  0001–0013: RLS op `users` uit → na 0014 aan; (b) productie-simulatie (zelfde keten + handmatig RLS
  aan): vóór/na 0014 geen enkel verschil in RLS, policies, functie en grants; (c) verse omgeving na
  0014 identiek aan productie na 0014; (d) tweede run geeft geen verandering.

### 13.6 Vervolg
Zie roadmap-punt 7 (sectie 10) voor de definitieve volgorde. Eerstvolgende stap: security hardening,
alleen na een afzonderlijke expliciete GO. **Het volledige hardeningplan (voorstel, niets uitgevoerd)
staat in `docs/security-hardening-plan.md`**: 11 kleine stappen met per onderdeel probleem, oude/nieuwe
regel, betrokken code, tests, volgorde en rollback, plus een rollenmatrix en teststrategie. Nieuwe
bevindingen daaruit (11 t/m 15): gedeactiveerde gebruikers werken nog via directe API; PIN-hash en
-salt zijn voor elke rol leesbaar; `users` is voor elke rol leesbaar; geen afdeling/bedrijf-controle
op rekeningen; goedkeuringslink is voor bediening zichtbaar (ontwerpkeuze).

### 13.7 STAP 0 — Voorbereiding en testharnas (2026-10-08, alleen voorbereiding)
**Geen productiewijziging.** Alles staat in `supabase/hardening/` (zie README daar). Opgeleverd:
`prod-readonly-checks.sql` (alleen lezen, 65 controles), `staging-seed.sql` (restaurant A/B/C, alle rollen,
gedeactiveerde gebruiker, wees-account), testharnas (`hardening_test`, 168 cases in 14 categorieën, per case
verwachting nu/na stap N), rechtenbaseline (55 rijen) en de migratie/rollback-structuur voor de 11 stappen.
* **Lokaal bewezen** (Postgres 16, schone keten 0001–0014 + productierechten): `run(0)` = 168/168 PASS; elke test
  wordt teruggedraaid (data ongewijzigd); 91 cases zijn "bekende zwaktes" die in een latere stap omslaan.
  Controles-query getest op een lege DB, op seeddata en met bewust ingebrachte fouten (geen owner, cross-restaurant,
  verkeerd opslagpad, wees-account): geeft de juiste BLOCKER/WARNING; draait met `default_transaction_read_only=on`.
* **Bewezen: de huidige uitnodigflow faalt.** Test TM06: een owner kan via de eigen verbinding geen `users`-rij
  invoegen (`new row violates row-level security policy for table "users"`). `inviteUser` stuurt dus eerst de mail
  en maakt het auth-account, en faalt daarna op het profiel → wees-account zonder opruiming. Oplossing = stap 3.
* **Service-role inventaris** (basis voor stap 2/7/11, nog niets verlaagd): publieke goedkeuring — SELECT approvals,
  receipts, receipt_lines, companies; UPDATE approvals, receipts; INSERT activity_log, domain_events ·
  ping-supabase — SELECT restaurants · uitnodiging — alleen auth-admin-API · gepland team-service — users I/U/D ·
  PIN-verificatie — SELECT approval_settings. Alle andere tabellen hebben geen service-role-gebruik.
* **Service-role + triggers:** de gepland guard-triggers krijgen géén algemene service-role-bypass. De publieke
  goedkeuring (approvals pending→approved/rejected; receipts pending_approval→locked/linked) wordt een smalle
  SECURITY DEFINER-functie (alleen EXECUTE voor service_role) die een transactie-lokale vlag zet. Besluit in stap 7.
* **Gecorrigeerde aanname in het plan:** H9 (`is_active`) geldt direct alleen voor policies die `my_restaurant_id()`
  gebruiken (daily_closings, users). Overige policies gebruiken een inline subquery; de afsluiting van
  gedeactiveerde gebruikers komt dus stap voor stap (2–9). Optie D9: een RESTRICTIVE "alleen actieve gebruikers"-policy
  per tabel (behalve `users`) zodat het in één keer dicht kan — open beslispunt.
* **Verwijderen van gebruikers met historie** wordt door foreign keys geblokkeerd (bonnen, dagafsluitingen, logs
  verwijzen naar `users`). In de praktijk: deactiveren, niet verwijderen (relevant voor stap 3 en de owner-constraint).
* **VIEW_REVENUE** staat in de matrix maar wordt in geen enkele route/pagina gebruikt (baseline-ambiguïteit).
* **Open beslispunten:** D6 (factuur draft→paid), D4 (account stuctech@gmail.com: alleen onderzocht, niet verwijderd),
  D9 (restrictive actief-policy), plus D1/D2/D3/D5/D7/D8 uit het plan.
* **Nog te doen door Dick (productie, alleen lezen):** `supabase/hardening/prod-readonly-checks.sql` draaien en het
  resultaat terugsturen. Tot dan zijn de datacompatibiliteit, het productie-fingerprintvergelijk (repo ↔ productie) en D4
  onbeoordeeld.

### 13.8 STAP 0 — Uitkomst productiecontrole (2026-10-08, `prod-readonly-checks.sql` door Dick gedraaid)
Productie bevat uitsluitend testdata: 1 restaurant (Café Restaurant Polder), 2 gebruikers (1 owner, 1 bediening, geen
gedeactiveerde), 5 bonnen, 4 facturen, 4 betalingen, 3 documenten, 2 dagafsluitingen. **Geen BLOCKER.**
* **Repo ↔ productie:** fingerprints policies (A04), storage-policies (A05), kolommen (A07) en check-constraints (A08)
  zijn **identiek** aan de repo-keten. Twee verschillen: (1) de brontekst van `my_restaurant_id()` in productie
  (md5 `c6ceb8cf…`) wijkt af van de repo (md5 `dfe36a32…`) — SECURITY DEFINER/stable gelijk, inhoud nog niet
  vergeleken (vermoedelijk witruimte of `public.`-prefix); vóór stap 1 eerst de productietekst lezen; (2) productie
  heeft de functie `rls_auto_enable()` (SECURITY DEFINER, search_path=pg_catalog) die de repo niet kent (Supabase-
  platformfunctie die RLS op nieuwe tabellen aanzet). Niet gecorrigeerd, alleen gerapporteerd.
* **Opgelost na aanvullende alleen-lezen query:** de productiedefinitie van `my_restaurant_id()` is inhoudelijk
  **identiek** aan de repo (`select restaurant_id from users where id = auth.uid()`, SQL, STABLE, SECURITY DEFINER,
  geen `search_path`). Het md5-verschil komt uitsluitend door **CRLF-regeleinden** in productie (md5 van de bron met
  `\r\n` = `c6ceb8cf…`, bewezen). Execute-rechten: `PUBLIC` en `postgres` (dus ook `anon`). `rls_auto_enable()` is een
  event-trigger-functie (plpgsql, SECURITY DEFINER, `search_path=pg_catalog`) die RLS aanzet op nieuwe tabellen in
  `public`; execute: `PUBLIC` en `postgres`; alleen gedocumenteerd, niet te wijzigen of te vervangen. Geen blocker voor stap 1.
* **Datacompatibiliteit:** owner-integriteit OK; geen cross-restaurant of cross-bedrijf verwijzingen; alle storage-paden
  conform; geen `integration_plugins`; statussen binnen de geplande state machine (receipts: linked 2, locked 5;
  facturen: draft 1, paid 3, nooit sent/overdue). WARNING: `approval_settings` bevat 1 `pin_hash` (leesbaar voor elke rol)
  bij methode qr; `my_restaurant_id` zonder vast search_path.
* **D6-indicatie:** 1 betaalde factuur zonder "sent" in het logboek — mogelijk draft → paid. Niet beslist.
* **D4:** `stuctech@gmail.com` bestaat (aangemaakt 2026-07-05, bevestigd, nooit ingelogd, geen profiel = wees-account).
  Niets verwijderd. Relevant voor stap 3: dit e-mailadres kan niet opnieuw worden uitgenodigd zolang het auth-account bestaat.

### 13.9 HARDENING STAP 1 — H1 + H9 helpers (migratie 0015, 2026-10-08)
**Alleen functies.** Migratie `supabase/migrations/0015_hardening_step1_helpers.sql`, rollback `supabase/rollbacks/0015_rollback.sql`.
* `my_restaurant_id()` herdefinieerd: zelfde semantiek, `set search_path = public, pg_temp`, `public.users`, `and is_active`
  (fail closed: geen uid / geen profiel / inactief → NULL). Nieuw: `my_role()`, `role_has_permission(role, perm)` (exacte kopie van
  PERMISSIONS; onbekende of NULL rol/permissie → `false`, nooit NULL; niet SECURITY DEFINER) en `has_perm(perm)`.
* EXECUTE: ingetrokken voor PUBLIC/anon, alleen `authenticated` en `service_role`. `rls_auto_enable()` en alle overige functies ongemoeid.
* Niet gewijzigd: policies, tabelrechten, triggers, storage, data (policy-fingerprint en grants-fingerprint vóór/na identiek).
* Gevolg (bedoeld): een gedeactiveerde gebruiker verliest leesrecht op `daily_closings` en teamleden en kan zijn eigen `users`-rij niet
  meer wijzigen; eigen profiel blijft leesbaar (middleware). Andere tabellen volgen in stap 2–9 (zie D9).
* Gevonden en gedicht: vóór stap 1 kon een gebruiker via een eigen tijdelijke tabel `users` (pg_temp staat vooraan in het zoekpad) de
  uitkomst van `my_restaurant_id()` omleiden en daarmee de dagafsluitingen van een ander restaurant lezen (tests HP48/HP50).
* Tests (lokaal, schone keten + productierechten): vóór 0015 218/218 PASS (huidige stand); na 0015 `run(1)` 218/218 PASS;
  rollback → `run(0)` 218/218; opnieuw toepassen en dubbel draaien (idempotent) 218/218. Matrix SQL ↔ TypeScript: 55/55 gelijk, direct
  uit `role-helpers.ts` geparsed. 50 nieuwe cases (categorie HELPERS); RE08/RE10 gaan van stap 3 naar stap 1 (inactieve gebruiker kan zichzelf
  niet meer promoveren/heractiveren). Nog te doen: Dick draait 0015 in productie en daarna de alleen-lezen controle uit het rapport.

### 13.10 HARDENING STAP 2 — H3 restaurants + H8a rechten (migratie 0016, 2026-10-08)
Migratie `supabase/migrations/0016_hardening_step2_restaurants_privileges.sql`, rollback `supabase/rollbacks/0016_rollback.sql`.
* **H3:** policy "tenant isolation restaurants" (for all) vervangen door SELECT-policy "restaurants read own" (`id = my_restaurant_id()`);
  INSERT/UPDATE/DELETE op `restaurants` ingetrokken voor `authenticated`. Controle in de code: er wordt nergens naar `restaurants`
  geschreven; er zijn drie leesplekken (naam voor factuur/mail door ingelogde gebruiker) en de service-role ping — alle blijven werken.
* **H8a:** TRUNCATE/TRIGGER/REFERENCES ingetrokken voor anon, authenticated en service_role op alle tabellen in public; anon verliest
  alle rechten op bestaande tabellen en sequences; standaardrechten voor nieuwe tabellen: geen TRUNCATE/TRIGGER/REFERENCES.
  SELECT/INSERT/UPDATE/DELETE van authenticated en service_role op alle andere tabellen is **ongewijzigd** (least privilege per tabel = stap 11).
* Niet gewijzigd: overige policies, functies, triggers, storage, data (fingerprints vóór/na gelijk).
* Gevolg: een gedeactiveerde gebruiker kan zijn restaurant niet meer lezen; verwijderen van een restaurant (cascade) kan alleen nog
  de databasebeheerder/service-role.
* Tests (lokaal): vóór 0016 235/235; na 0016 `run(2)` 235/235; rollback = exacte vóór-stand (policy, rechten); dubbel draaien idempotent.
  Nieuw: RS07–RS14 en PR20–PR28 (17 cases).
* **Productie (2026-10-08, Dick):** vóór-stand vastgelegd; migratie 0016 zonder fouten gedraaid; controle: alleen policy "restaurants read own"
  (SELECT), anon zonder tabelrechten, authenticated SELECT 25 / INSERT-UPDATE-DELETE 24, service_role DML 25, geen TRUNCATE/TRIGGER/REFERENCES.
  App-regressie als eigenaar (dashboard, rekeningen, facturen, logboek) werkt. **Stap 2 is akkoord.**
* **Genoteerd voor stap 11 (niet nu):** het recht MAINTAIN staat nog bij anon/authenticated/service_role (ook in de standaardrechten van
  `postgres` in `public`: anon=m, authenticated/service_role=arwdm); vóór-stand had geen sequences in `public`. Standaardrechten van
  `supabase_admin` (platform) zijn niet aan te passen en vallen buiten onze migraties.
* **Dashboard-opmerking (los van hardening):** "Omzet deze maand" telt op `issued_at` van de factuur, niet op betaaldatum.


### 13.11 HARDENING STAP 3 — H2 users + server-side teambeheer (migratie 0017 + app-code, 2026-10-08)

**Status: lokaal volledig getest; productie wacht op Dicks uitvoering (volgorde: eerst app-deploy, dan migratie).**

* **Database (0017):** `users` verliest INSERT/UPDATE/DELETE voor `authenticated` (grants ingetrokken) en de twee team-policies (update/delete) vervallen. Nieuw: `users_guard` (id en restaurant_id onveranderlijk, ook voor service-role) en `users_keep_owner` (deferrable constraint trigger: minstens één actieve owner per restaurant, geserialiseerd via `for no key update` op de restaurantrij). SELECT-policies ongewijzigd (D2 blijft open).
* **App:** alle schrijfacties op `users` lopen via `lib/user-management/user-admin-repository.ts` (service-role) ná `requireRole("MANAGE_TEAM")`, elke query gescoped op het restaurant van de aanroeper. Uitnodigen: Auth-uitnodiging → profiel-check → profiel; bij fout wordt een zojuist (<120 s) aangemaakt Auth-account opgeruimd (geen wees-account). Verwijderen ruimt ook het Auth-account op (met waarschuwing als dat mislukt). Gebruikers met historie worden gedeactiveerd, niet verwijderd.
* **Tests:** 251 cases (incl. de oorspronkelijke 168): voor 0017 251/251 PASS (stap 2), na 0017 250 PASS + 1 OPEN (TM11/D2). App-integratietest van team-service tegen echte Postgres (nep-Supabase-client): 32/32 PASS zowel vóór als ná 0017. Rollback exact, migratie idempotent, concurrency-check OK. `npm run build` OK.
* **Beperkingen:** een verstuurde uitnodigingsmail kan niet worden teruggehaald; de echte Auth Admin API is lokaal niet te testen (nagebootst); wees-account stuctech@gmail.com blokkeert opnieuw uitnodigen van dat adres tot D4 is besloten (niet verwijderd).

### 13.12 HARDENING STAP 4 — H5a logboeken append-only (migratie 0018, 2026-10-08)

**Status: lokaal volledig getest; productie wacht op Dicks uitvoering. Geen app-wijziging nodig.**

* **Tabellen:** `activity_log`, `audit_log`, `domain_events`. Bestaande logdata blijft ongewijzigd.
* **Policies:** de "for all"-policies zijn vervangen door per tabel een SELECT-policy (eigen restaurant via `my_restaurant_id()`) en een INSERT-policy (eigen restaurant en onder eigen naam: `user_id` / `changed_by` / `published_by` = `auth.uid()`).
* **Rechten:** `authenticated` verliest UPDATE en DELETE op de drie tabellen (SELECT en INSERT blijven). Service-role rechten zijn niet verlaagd (inventaris in stap 11).
* **Append-only vangnet:** trigger `logs_append_only` (BEFORE UPDATE/DELETE, rij) en `logs_no_truncate` (BEFORE TRUNCATE) op alle drie de tabellen, geldig voor ÍEDEREEN (ook service-role en postgres). Geen algemene service-role-uitzondering. Enige smalle uitzondering: DELETE van logregels van een restaurant dat zelf al verwijderd is (cascade).
* **Server-side logwrites** (publieke goedkeuring, service-role, actor NULL) blijven werken. Authenticated schrijvers moeten sinds deze stap een actor invullen (alle 35 bestaande insert-plekken in de app doen dat).
* **Gevolgen om te weten:** (1) een gedeactiveerde gebruiker kan logs niet meer lezen of schrijven (volgt `my_restaurant_id()`, zie D9); (2) de app negeert fouten van log-inserts (bestaand gedrag, niet gewijzigd): een geweigerde logwrite geeft dus geen foutmelding in de UI.
* **Niet gedaan (bewust):** H5b (alle logs via server), cross-reference-check van de actor (stap 5), service-role-rechten verlagen (stap 11).
* **Tests:** 297 cases; vóór 0018 296 PASS + 1 OPEN (TM11/D2), na 0018 296 PASS + 1 OPEN. Rollback exact, migratie idempotent. App-test teambeheer 32/32 PASS. `npm run build` OK.

### 13.13 HARDENING STAP 5 — H7 cross-reference integriteit (migratie 0019, 2026-10-08)

**Status: lokaal volledig getest; productie wacht op Dicks uitvoering. Geen app-wijziging, geen data-wijziging.**

* **Waarom:** een gewone foreign key controleert alleen of de verwezen rij bestaat, niet van welk restaurant of bedrijf die is. Triggers (`BEFORE INSERT/UPDATE`, SECURITY DEFINER, ook voor service-role en postgres, géén bypass) toetsen dat nu wel.
* **Beschermde relaties (kind → ouder):** `open_tabs` → bedrijf, afdeling, kostenplaats, project, contact (restaurant én bedrijf); `cost_centers.department_id` (zelfde bedrijf); `receipts.open_tab_id`; `invoices.company_id`; `invoice_lines` (factuur en bon, zelfde restaurant); `approvals` (bon en bedrijf, zelfde restaurant); `configurations` en `workflow_rules` → bedrijf; `documents` → factuur (alleen `related_table = 'invoices'`); gebruikersverwijzingen `receipts.created_by`, `daily_closings.closed_by/reopened_by`, `notifications.recipient_user_id`, en bij INSERT `activity_log.user_id`, `domain_events.published_by`, `audit_log.changed_by` → gebruiker in hetzelfde restaurant.
* **Ouder-kant:** de sleutelkolommen waarlangs die controles lopen zijn onveranderlijk (`companies.restaurant_id`; `company_id` van afdeling, kostenplaats, project, contact; `restaurant_id` van rekening, bon, factuur). Anders kan een ouder achteraf "verhuizen" en de controle omzeilen. De app wijzigt deze kolommen nergens.
* **Triggers:** 23 stuks (`xref_open_tabs`, `xref_cost_centers`, `xref_receipts`, `xref_invoices`, `xref_invoice_lines`, `xref_approvals`, `xref_company_scoped` ×2, `xref_documents`, `xref_user_ref` ×6, `xref_keys_immutable` ×8) met 11 functies. De functies zijn voor niemand rechtstreeks uitvoerbaar.
* **Veiligheidsstop in de migratie:** schendt bestaande data één van de regels (zelfde checks als B30–B42 in `prod-readonly-checks.sql`), dan stopt de migratie vóór er iets verandert.
* **Bewuste uitzonderingen (niet geblokkeerd):** (1) een rekening zónder bedrijf mét afdeling/kostenplaats/project/contact uit het eigen restaurant (er is geen bedrijf om tegen te toetsen; de tenant-grens geldt wel); (2) een bon van een ander bedrijf binnen hetzelfde restaurant op een factuur (alleen de restaurantgrens is vastgelegd in Stap 0); (3) `documents` met een andere `related_table` dan `invoices`; (4) `activity_log.target_id`, `audit_log.record_id` en andere vrije verwijzingen (geen foreign key, informatief); (5) tabellen met één ouder (`payments`, `approval_settings`, `company_codes`, `departments`, `projects`, `contacts`): daar volgt het restaurant uit de ouder, dus er is niets te vergelijken.
* **Tests:** 348 cases; vóór 0019 347 PASS + 1 OPEN (TM11/D2), na 0019 347 PASS + 1 OPEN. 39 cases die vóór 0019 een zwakte bewezen, zijn na 0019 geweigerd; alle geldige relaties blijven werken. Rollback exact, migratie herhaalbaar, veiligheidsstop getest. App-test teambeheer 32/32 PASS. `npm run build` OK.

### 13.14 HARDENING STAP 6 — H6 storage (migratie 0020 + app-wijziging, 2026-10-08)

**Status: in productie (2026-10-08, eerst app-deploy, dan migratie) gecontroleerd en door Dick goedgekeurd.** Productiecontrole: precies 2 nieuwe policies voor `{authenticated}`, de 4 bestaande bestanden intact, geen afwijkende paden; nieuwe factuur 2026-0006 met PDF correct opgeslagen (`upsert:false`).

* **Pad-structuur ongewijzigd:** `{restaurant_id}/invoices/{invoice_id}.pdf`. Bestaande bestanden blijven leesbaar (Stap 0: alle paden hebben dit patroon).
* **Policies op `storage.objects` (bucket `documents`):** de drie oude policies (lezen, uploaden, bijwerken, alleen op restaurantmap) zijn vervangen door twee: `documents bucket read` en `documents bucket upload`, alleen voor `authenticated`. Voorwaarde: eerste padonderdeel = `my_restaurant_id()` én recht `MANAGE_INVOICES` (owner en administratie, gelijk aan de routes). Gedeactiveerde gebruikers vallen af (helpers uit Stap 1). Een pad zonder uuid geeft een nette weigering in plaats van een cast-fout.
* **Geen UPDATE- en geen DELETE-policy:** bestanden zijn voor gebruikers onveranderlijk (overschrijven en verwijderen geweigerd).
* **App:** `generate-invoice` uploadt nu met `upsert: false` (het pad bevat de nieuwe factuur-id, dus er is nooit een bestaand bestand). `pdf-url` (signed URL, `MANAGE_INVOICES`) is ongewijzigd.
* **Niet aangepast:** de rechten op het storage-schema zelf (beheerd door Supabase). **Bekende restrisico's:** service-role (server-side) omzeilt RLS en kan nog schrijven en verwijderen; de app gebruikt dat niet voor storage. Een trigger op de door Supabase beheerde tabel `storage.objects` is bewust niet toegevoegd. Het echte Storage-API-gedrag (upload, signed URL) is lokaal niet te testen; de policies zijn getest op tabelniveau.
* **Gevolg:** een manager of bediening kan factuur-PDF's niet meer rechtstreeks via de Storage-API lezen. De app liet dat al niet toe.
* **Tests:** 368 cases; vóór 0020 367 PASS + 1 OPEN (TM11/D2), na 0020 367 PASS + 1 OPEN. 12 cases die vóór 0020 een zwakte lieten zien, zijn na 0020 geweigerd. Rollback exact, migratie herhaalbaar. App-test teambeheer 32/32 PASS. `npm run build` OK.

### 13.15 HARDENING STAP 7 — H4a rekeningen, bonnen, goedkeuringen (migratie 0021, 2026-10-08)

**Status: in productie (2026-10-09) gecontroleerd; app-test door Dick: goedkeuren (vergrendeld, geen bewerk-/verwijderknoppen meer), afwijzen en sluiten bevestigd. Wacht op beoordeling. Geen app-wijziging, dus geen deploy-volgorde.**
Migratie `supabase/migrations/0021_hardening_step7_tabs_receipts.sql`, rollback `supabase/rollbacks/0021_rollback.sql`, controlequeries `supabase/hardening/prod-step7-checks.sql`.

* **Policies (13, alle `to authenticated`; de vier "tenant isolation … for all"-policies zijn vervangen):**
  `open_tabs` select/insert/update/delete met `MANAGE_OPEN_TABS` (insert alleen status `open`); `receipts` idem met `MANAGE_RECEIPTS` (insert alleen `draft` of `linked`); `receipt_lines` alleen select + insert (via een bon uit het eigen restaurant, `MANAGE_RECEIPTS`; de app wijzigt of verwijdert nooit rechtstreeks een regel); `approvals` select/insert met `MANAGE_RECEIPTS` (insert alleen `pending`), update met `APPROVE_RECEIPTS`, **geen delete-policy**. Alles hangt aan `my_restaurant_id()` en `has_perm()` (Stap 1), dus gedeactiveerde gebruikers en keuken (D1) hebben hier geen toegang meer.
* **Vier vangnet-triggers, voor IEDEREEN (ook service-role en postgres; geen algemene bypass):**
  * `receipts_guard`: nieuwe bon alleen `draft`/`linked` en alleen aan een **open** rekening; `draft|linked → pending_approval` (bonnenbeheer); `pending_approval → approved|locked` en `approved → locked` alleen met `APPROVE_RECEIPTS`; afwijzen `pending_approval → linked` met `APPROVE_RECEIPTS`; in `pending_approval`, `approved` en `locked` is behalve de status **geen enkel veld** te wijzigen; zo'n bon is niet te verwijderen; een bon van een gefactureerde rekening is onveranderlijk en niet te verwijderen; verhuizen kan alleen naar een open rekening. Vrije statussen (`draft`, `validated`, `linked`, `submitted`) onderling zijn niet beperkt: daar is geen businessregel voor.
  * `receipt_lines_guard`: regels alleen toevoegen, wijzigen of verwijderen zolang de bon `draft` of `linked` is (cascade bij het verwijderen van de bon blijft werken).
  * `open_tabs_guard`: nieuwe rekening alleen `open`; `open → closed` (rekeningenbeheer), `closed → invoiced` alleen met `MANAGE_INVOICES`; nooit terug, nooit `open → invoiced`; `invoiced` is volledig onveranderlijk; verwijderen alleen als `open` (bonnen houden de foreign key al tegen).
  * `approvals_guard`: nieuw alleen `pending` en leeg; `pending → approved|rejected|expired` eenmalig door `APPROVE_RECEIPTS` of door de publieke link (service-role); daarna volledig onveranderlijk; bon, bedrijf, methode, verificatiecode en aanvraagtijd zijn altijd onveranderlijk; rechtstreeks verwijderen is voor niemand mogelijk (alleen cascade als de bon zelf wordt verwijderd).
* **Service-role:** exact de twee overgangen van de publieke goedkeuringslink blijven mogelijk (`bon pending_approval → locked | linked`, `approval pending → approved | rejected | expired`). De eerder overwogen SECURITY DEFINER-functie met vlag bleek niet nodig: de trigger ziet via `current_user` of de aanroep van service-role komt, en dat is niet te vervalsen door een gebruiker. Daardoor is er **geen codewijziging** in `public-approve`.
* **Cascade-herkenning:** een delete uit een andere trigger (`pg_trigger_depth() > 1`) bij een restaurant dat al weg is, wordt toegestaan, zodat het verwijderen van een heel restaurant blijft werken. (Eerste versie keek naar de rolnaam; dat bleek lokaal te breken omdat de tabeleigenaar daar anders heet. Nu onafhankelijk van rolnamen.)
* **Gevolgen voor de app (bedoeld):** een bon in wacht, goedgekeurd of vergrendeld is in de database echt vast. De UI verbergt bewerken/verwijderen al voor `pending_approval` en `locked`; alleen een bon met status `approved` (alleen bij `autoLock = uit`) toont nog knoppen, die nu een databasefoutmelding geven in plaats van te slagen. De route `PATCH /api/receipts/[id]` blokkeerde alleen `locked`; de database dekt nu ook de andere beschermde statussen.
* **Niet gedaan (bewust):** invoices/payments/documents (H4b), logs, D1–D9 (D6 niet beslist), grants (stap 11), UTC-weergave. Verwijderen van een heel restaurant met goedkeuringen faalt al vóór deze stap op `approvals.company_id` (foreign key zonder cascade); niet gewijzigd.
* **Open punten die tijdens de app-test boven kwamen (bestonden al vóór stap 7, bewust niet in deze stap, elk met eigen GO):** (1) de UI heeft geen knop "Opnieuw indienen" voor een afgewezen bon (de route `request-approval` werkt wel, maar niets roept hem aan; nu is verwijderen en opnieuw invoeren de enige weg); (2) een afgewezen bon is weer `linked` en gaat gewoon mee op een factuur, want `generate-invoice` blokkeert alleen bonnen in wacht (bedrijfsbeslissing nodig, bijvoorbeeld een aparte status `rejected`); (3) een gesloten rekening kan niet heropend worden (geen functie; heropenen zou een eigen, gelogde flow nodig hebben); (4) een goedgekeurde bon is onomkeerbaar (correctie via creditnota is een latere fase).
* **Tests:** 476 cases (108 nieuw, categorie REKENINGEN): vóór 0021 475 PASS + 1 OPEN (TM11/D2), na 0021 475 PASS + 1 OPEN; de nieuwe cases die vooraf een zwakte lieten zien zijn na 0021 geweigerd. Rollback exact (policies, triggers, functies, grants, data identiek aan vóór stap 7), migratie herhaalbaar. **App-regressie langs de echte route-handlers** tegen de lokale database: 56/56 PASS (rekening openen, bon met regels, goedkeuring aanvragen, intern goedkeuren, publieke link goedkeuren/afwijzen/opnieuw indienen, autoLock uit, factureren met `upsert:false`, verwijderen, dashboard en dagafsluitingsrapport, directe pogingen buiten de app om); zonder 0021 falen 20 daarvan. `tsc` en `npm run build` OK.

## 12. STATUS

**Architectuur: BEVROREN — v1.0** (kernblueprint) + **v1.21 goedgekeurde uitbreiding** (Approval Engine + Bedrijfsreferenties, sectie 8) + **Daily Closing Engine** (sectie 9) + **drie-fasen-roadmap** (sectie 10: Administratieplatform ✅ → Integratieplatform → Financieel platform). **Implementatie: Fase 1 (Administratieplatform) COMPLEET** — Fase 1 kernmodules, Fase A/A.5/B/C, Daily Closing, rechtenmatrix, Factuurstatus + Betalingen (v1.42), alle bekende RLS/GRANT-gaten gedicht. **Fase 0 (audit) en baseline (0014) zijn klaar (sectie 13); volgende gebouwde stap: security hardening (na expliciete GO, roadmap-punt 7).** Eerder: Resend-domein activeren (wacht op restauranthouder), daarna Fase D (digitale handtekening) — daarna pas Fase 2 (Integratieplatform) en Fase 3 (Financieel platform/Payment Engine, v1.43).** Dit document staat per sectie 3 boven aannames.

**Voor een nieuwe sessie/instantie:** begin bij `README.md` sectie "🚦 Start hier" — die bevat de volledige overdracht (huidige stand, eerstvolgende actie, aangehouden werkwijze, bekende valkuilen).
 
    
