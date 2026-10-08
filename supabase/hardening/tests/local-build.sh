#!/usr/bin/env bash
# Bouwt een LOKALE testdatabase (Postgres, géén Supabase) en draait seed + harnas + cases.
# Gebruik:  PSQL="psql -X -q -p 55432 -h /socketdir" ./local-build.sh   (vanuit supabase/hardening/tests)
set -euo pipefail
PSQL=${PSQL:-"psql -X -q"}; DB=${DB:-polder_stage}
cd "$(dirname "$0")/../.."          # = supabase/
$PSQL -d postgres -c "drop database if exists $DB" -c "create database $DB"
P="$PSQL -v ON_ERROR_STOP=1 -d $DB"
$P -f hardening/tests/local-stub.sql
for f in migrations/00{01..14}_*.sql; do echo "migratie $f"; $P -f "$f" >/dev/null; done
$P -f hardening/tests/local-prodgrants.sql   # = rechten zoals productie vóór stap 1
for f in migrations/001[5-9]_*.sql migrations/00[2-9]?_*.sql; do [ -e "$f" ] || continue; echo "hardening-migratie $f"; $P -f "$f" >/dev/null; done
python3 hardening/tests/generate_cases.py > hardening/tests/10_cases.sql
$P -f hardening/staging-seed.sql -f hardening/tests/00_harness.sql -f hardening/tests/10_cases.sql
echo "klaar. Draai:  select * from hardening_test.summary(0);"
