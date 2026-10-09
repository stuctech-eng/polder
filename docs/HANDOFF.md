# HANDOFF — waar we gebleven zijn (bijgewerkt 9 okt 2026, 20:55)

Doel van dit bestand: elke nieuwe sessie kan hier verder zonder iets te missen. Details staan in `docs/architecture.md` (sectie 13.16, changelog v1.61/v1.62) en `supabase/hardening/README.md`.

## Wat staat LIVE
- Hardening stappen 0–7a + migratie 0022 (approvals_guard aangescherpt) in productie, akkoord.
- **Plan 7b app (commit 5f1966f, v1.0.74)**: een afgewezen bon kan niet gefactureerd worden totdat hij opnieuw is ingediend en goedgekeurd (`generate-invoice` blokkeert vóór elke schrijfactie, fail closed); knop "Opnieuw indienen" en waarschuwing op de rekening.
- Productie-database staat op **migratie 0022**.

## Wat is VOORBEREID maar NIET UITGEVOERD
- **Migratie 0023** (`supabase/migrations/0023_hardening_plan7b_invoice_block.sql`, rollback `supabase/rollbacks/0023_rollback.sql`): extra databaseslot op `closed -> invoiced`. **Niet uitgevoerd in productie; voorlopig laten vallen** (besluit Dick, 9 okt). Gevolg: de app-blokkade is de enige verdediging; directe databasewijzigingen worden niet geweigerd.
- Tests/controles: `tests/preflight-0023-tests.sh` (59 checks), `tests/app-regression/` (t7 173 checks, t8 39 checks), `prod-step7b-checks.sql`, `prod-step7b-preflight-verdict.sql`, 14 gedeelde scenario's (`invoice-block-scenarios.json`), 542 databasecases (541 PASS + 1 OPEN).
- Productiefeiten (read-only gemeten 9 okt): `open_tabs_guard` fingerprint `dc970c3a71212b9b27352ae989d437b1` en `approvals_guard` `d84e5483f3bad1bcb48aa443a2e16644` = de bestandsversies ZONDER `--`-commentaar (kopieerblokken lieten commentaar weg). ACL's en trigger kloppen. Voor 0023 zijn per functie precies twee bekende versies toegestaan (met/zonder commentaar). Kopieerblokken voor productie voortaan EXACT gelijk aan het bestand.
- Deze bestanden staan op branch `plan-7b-0023-voorbereid` (niet op main).

## Volgende stappen (elk met eigen expliciete GO)
1. Live app testen: bon afwijzen → opnieuw indienen → goedkeuren → factureren; en bevestigen dat een afgewezen bon niet gefactureerd kan worden. Werkt de blokkade niet goed: eerst oplossen.
2. **Read-only audit voor meerdere restaurants**: restaurantkoppeling, database, RLS, gebruikersrechten (geen code/migraties/deploys tijdens de audit). Bestaande beveiliging van restaurantgegevens expliciet meenemen.
3. Audit beoordelen → implementatieplan → pas na GO bouwen.
4. Later (alleen met GO): 0023 heropenen (eerst productieverdict, dan kopieerblok), Step 8 (invoices/payments/documents, migratie 0024), platform-admin, restaurantbeheer, UI, integraties, privacy.

## Open punten (niet vergeten)
- TM11/D2 blijft OPEN. D1–D9, UTC-weergavefout, Resend-domeinverificatie, receipt-pagina ververst niet automatisch, gesloten rekening heropenen, creditnota, Step 11 (grants), orphan account D4 (niet verwijderen), `rls_auto_enable()` nooit wijzigen.

## Werkafspraken (kort)
- Audit → plan → expliciete GO per stap → bouwen → lokaal testen → productiecontrole → STOP → gezamenlijke review → nieuwe GO. GPT adviseert/beoordeelt, Claude beslist/implementeert.
- Productieacties als genummerde stappen, EEN stap per bericht, SQL als kopieerblok in de chat; na elke stap stoppen.
- Push alleen op Dick's expliciete "push"; bericht over pushstatus begint met 🟢 KAN GEPUSHT WORDEN (getest + GPT akkoord) of 🟡 NOG NIET PUSHEN. Commit-stijl: `polder <naam> — v1.0.NN — <d> okt 2026, HH:MM`. Laatste versie op main: v1.0.74.
- Geen algemene service_role-bypass in triggers; service_role-rechten niet blind verwijderen (eerst inventaris, Step 11).
