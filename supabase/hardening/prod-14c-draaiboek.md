# Draaiboek productie stap 14c — handtekening van de klant

Status: lokaal klaar en beoordeeld (REVIEW GO, 17 okt 2026). **Nog niets gepusht, niets in productie.** Elke push en elke
productiestap vraagt een eigen, expliciete GO van Dick. Eén stap per bericht; na elke stap stoppen en beoordelen.

## Stopregel (geldt bij elke stap)

Wijkt een uitkomst ook maar in één veld af van de verwachte waarde hieronder, of geeft een blok een foutmelding:
**stoppen.** Niets repareren, geen volgende migratie, geen rollback op eigen houtje. Eerst de uitkomst letterlijk terugplakken
en samen uitzoeken waarom. Een migratie die "vooraf: stand wijkt af" meldt, heeft niets gewijzigd.

## Controleblokken (alleen lezen, beginnen met `begin`, eindigen met `rollback`)

- **A** = `supabase/hardening/prod-teken14c-checks.sql` — kolommen: `stand | bits | nieuw_ok | wachten | wachten_md5 | bestaand_md5`
- **F** = `supabase/hardening/prod-teken14c-functie.sql` — kolommen: `oordeel | code_md5 | verwacht | kenmerken_ok | recht | aantal_versies`

`bestaand_md5` heeft geen vaste waarde: hij moet bij **elke** stap exact gelijk zijn aan de waarde van de nulmeting (stap 0).

## Volgorde

| Stap | Actie | A: stand / bits / nieuw_ok / wachten / wachten_md5 | F: oordeel / kenmerken_ok / recht / aantal_versies |
|---|---|---|---|
| 0 | nulmeting: A en F draaien, `bestaand_md5` noteren | `0042 / 000000 / true / 0 / d84e54,9d3540` | `ONTBREEKT / false / (leeg) / 0` |
| 1 | `0043_handtekening_module.sql` | `0043 / 100000 / true / 0 / d84e54,9d3540` | `ONTBREEKT / false / (leeg) / 0` |
| 2 | `0044_handtekening_bonwacht.sql` | `0044 / 110000 / true / 0 / d84e54,50feb6` | `ONTBREEKT / false / (leeg) / 0` |
| 3 | `0045_handtekening_regelwacht.sql` | `0045 / 111000 / true / 0 / f09a66,50feb6` | `ONTBREEKT / false / (leeg) / 0` |
| 4 | `0046_handtekening_teken_wacht.sql` | `0046 / 111100 / true / 2 / f09a66,50feb6` | `ONTBREEKT / false / (leeg) / 0` |
| 5 | `0047_bon_ondertekenen.sql` | `0047 / 111110 / true / 2 / f09a66,50feb6` | `GELIJK / true / {postgres=X/postgres} / 1` |
| 6 | `0048_bon_ondertekenen_recht.sql` | `0048 / 111111 / true / 2 / f09a66,50feb6` | `GELIJK / true / {postgres=X/postgres,authenticated=X/postgres} / 1` |

Bij F moeten `code_md5` en `verwacht` gelijk zijn (`083a2f1e742d35d6438bd70fad8d467d`) zodra de functie bestaat.

Aandachtspunten:
- **Stap 0 is ook een voorwaarde.** Is `wachten_md5` niet `d84e54,9d3540`, dan wijken de bewakingsfuncties in productie af van de
  stand die 0044/0045 verwachten (die breken dan veilig af). Stoppen en eerst uitzoeken.
- **Stap 5:** 0047 heeft geen eigen nacontrole meer (die zit in 0048). Na 0047 zijn A en F dus de enige controle: de functie
  moet bestaan, GELIJK zijn, en mag door niemand worden aangeroepen (`recht = {postgres=X/postgres}`).
- De module Handtekening staat na stap 1–6 voor elk restaurant **uit**. De huidige app merkt niets van de migraties (getest).

## Pushes en app (elk met eigen GO)

Zoals bij 14a in twee pushes, omdat de kopieerblokken exact gelijk moeten zijn aan het bestand op `main`:
- **Push A** (vóór stap 1): alleen database, controleblokken, tests en documentatie. Verandert de app niet.
- **Push B** (na stap 6): de app (route `/api/receipts/[id]/sign`, tekenscherm, instellingen, modulelijst). Gaat direct live via
  Vercel. Andersom (app eerst) is ook getest en veilig (module onbekend = uit), maar de voorgestelde volgorde is database eerst.

## Rooktest (na push B, door Dick)

1. Platformbeheer: module Handtekening aanzetten voor een testrestaurant.
2. Bij een testbedrijf methode "Handtekening van de klant" kiezen.
3. Bon toevoegen (wordt ingediend), "Laten tekenen door de klant", naam + handtekening, Bevestigen → "getekend door …".
4. Controleren dat PIN, QR/e-mail en "restaurant bevestigt" nog werken.

## Terugdraaien (alleen met eigen GO, strikt omgekeerd)

`0048_rollback` → `0047_rollback` → `0046_rollback` → `0045_rollback` → `0044_rollback` → `0043_rollback`, na elke stap A (en F)
draaien: de verwachte uitkomst is steeds de regel van de vorige stap in de tabel (lokaal gemeten: exact symmetrisch).
`0043_rollback` weigert als er al iets met handtekening bestaat (instelling, regel of module per restaurant): eerst beoordelen.

## Definitieve wijzigingsset (lokaal, 17 okt)

- Database: `0043`–`0048` + rollbacks; controleblokken A en F.
- App: `app/api/receipts/[id]/sign/route.ts`, `lib/approval/signature.ts`, `app/(dashboard)/open-tabs/[id]/signature-dialog.tsx`,
  `receipts-section.tsx`, `open-tabs/[id]/page.tsx`, `companies/[id]/page.tsx`, `sub-entities.tsx`,
  `api/companies/[id]/approval-settings/route.ts`, `lib/features/features.ts`, `lib/approval/auto-refresh.ts`.
- Tests: `handtekening-tests.sh` (165/165 op PostgreSQL 16 en 17), `t21` (29/29), `t22` (15/15), aangepast `t12`,
  harnas `generate_cases.py`/`10_cases.sql` (MG01, FW74); t7–t20 per regel gelijk aan de app van main (t7: dezelfde 14 bekende
  FAIL's van de niet-uitgevoerde 0023); typecontrole en `next build` geslaagd.

## Bekende beperkingen en open punten (bewust buiten 14c)

- Een opgeslagen handtekening is nog niet terug te zien in de app.
- Een handtekeningbon kan in de app niet worden afgewezen; herstel alleen door de beheerder in de SQL-editor met
  `set local role service_role` (lokaal getest, in productie nog niet uitgeprobeerd).
- Na het tekenen kan het bedrijf van de rekening nog wijzigen (geldt voor alle methoden).
- De PNG-controle kijkt naar begin, afmetingen en einde, niet naar controlegetallen en beeldgegevens in het midden.
- Tijdens een goedkeuring kan via de API nog een wachtende regel worden toegevoegd (bestaand probleem in de bewaking van 0022,
  alle methoden; aparte audit).
- Controleblok F: extra witruimte binnen een tekst geeft GELIJK (bewust); een functie met dezelfde naam in een ander schema wordt
  niet geteld (de app roept alleen `public` aan).
