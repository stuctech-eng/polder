#!/usr/bin/env bash
# Bouwt een LOKALE testdatabase (Postgres, géén Supabase) en draait seed + harnas + cases.
# Gebruik:  PSQL="psql -X -q -p 55432 -h /socketdir -U postgres" ./local-build.sh   (vanuit supabase/hardening/tests)
#   TOT=0022     bouw t/m 0022 = stand van productie vóór fase 1 (standaard: TOT=0024)
#   MET_0023=1   voeg ook de voorbereide, NIET in productie uitgevoerde migratie 0023 toe (toets met run(99))
set -euo pipefail
PSQL=${PSQL:-"psql -X -q"}; DB=${DB:-polder_stage}; TOT=${TOT:-0024}; MET_0023=${MET_0023:-0}
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
if [ "$TOT" = "0024" ]; then echo "migratie 0024 (tenantswitch)"; $P -f migrations/0024_tenantswitch_inline_policies.sql >/dev/null; fi
python3 hardening/tests/generate_cases.py > hardening/tests/10_cases.sql
$P -f hardening/tests/00_harness.sql -f hardening/tests/10_cases.sql >/dev/null
echo "klaar (t/m $TOT, 0023: $MET_0023). Draai:  select * from hardening_test.summary(8);"
