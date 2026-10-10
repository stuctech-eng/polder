#!/usr/bin/env bash
# Bouwt een LOKALE testdatabase (Postgres, géén Supabase) en draait seed + harnas + cases.
# Gebruik:  PSQL="psql -X -q -p 55432 -h /socketdir -U postgres" ./local-build.sh   (vanuit supabase/hardening/tests)
#   TOT=0022|0024|0025|0026|0027   bouw t/m die migratie (standaard 0027); 0022 = vóór fase 1, 0024 = vóór fase 2, 0025 = vóór platformbeheer
#   MET_0023=1   voeg ook de voorbereide, NIET in productie uitgevoerde migratie 0023 toe (toets met run(99))
set -euo pipefail
PSQL=${PSQL:-"psql -X -q"}; DB=${DB:-polder_stage}; TOT=${TOT:-0027}; MET_0023=${MET_0023:-0}
cd "$(dirname "$0")/../.."          # = supabase/
$PSQL -d postgres -c "drop database if exists $DB" -c "create database $DB"
P="$PSQL -v ON_ERROR_STOP=1 -d $DB"
$P -f hardening/tests/local-stub.sql
for f in migrations/00{01..14}_*.sql; do echo "migratie $f"; $P -f "$f" >/dev/null; done
$P -f hardening/tests/local-prodgrants.sql   # = rechten zoals productie vóór stap 1
for f in migrations/00{15..22}_*.sql; do echo "hardening-migratie $f"; $P -f "$f" >/dev/null; done
if [ "$MET_0023" = "1" ]; then echo "migratie 0023 (voorbereid, niet in productie)"; $P -f migrations/0023_hardening_plan7b_invoice_block.sql >/dev/null; fi
# seed = bestaande data nabootsen; de guards van stap 7 weigeren bijv. een direct aangemaakte gesloten rekening,
# daarom triggers alleen tijdens de seed uit
PGOPTIONS="-c session_replication_role=replica" $P -f hardening/staging-seed.sql >/dev/null
if [ "$TOT" != "0022" ]; then echo "migratie 0024 (tenantswitch)"; $P -f migrations/0024_tenantswitch_inline_policies.sql >/dev/null; fi
if [ "$TOT" = "0025" ] || [ "$TOT" = "0026" ] || [ "$TOT" = "0027" ]; then echo "migratie 0025 (restaurant aan/uit)"; $P -f migrations/0025_restaurant_aan_uit.sql >/dev/null; fi
# Supabase geeft nieuwe tabellen en functies standaard rechten aan anon/authenticated/service_role (na 0016 zonder TRUNCATE/TRIGGER/REFERENCES);
# 0026 moet dat zelf intrekken
$P -c "alter default privileges in schema public grant select, insert, update, delete on tables to anon, authenticated, service_role" \
   -c "alter default privileges in schema public grant all on functions to anon, authenticated, service_role" >/dev/null
if [ "$TOT" = "0026" ] || [ "$TOT" = "0027" ]; then echo "migratie 0026 (platformbeheer)"; $P -f migrations/0026_platformbeheer.sql >/dev/null; fi
if [ "$TOT" = "0027" ]; then echo "migratie 0027 (platformacties)"; $P -f migrations/0027_platform_acties.sql >/dev/null; fi
python3 hardening/tests/generate_cases.py > hardening/tests/10_cases.sql
$P -f hardening/tests/00_harness.sql -f hardening/tests/10_cases.sql >/dev/null
echo "klaar (t/m $TOT, 0023: $MET_0023). Draai:  select * from hardening_test.summary(9);"
