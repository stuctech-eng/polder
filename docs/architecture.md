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
│   └── Luistert naar: InvoiceGenerated, PaymentReceived, ImportFailed,
│                       OcrCompleted (bij lage zekerheid), ConnectorError
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

## 8. WIJZIGINGSHISTORIE

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

## 9. STATUS

**BEVROREN — v1.0.** Dit document is nu `docs/architecture.md` en staat per sectie 3 boven aannames. Implementatie van Fase 1 start hierna.
