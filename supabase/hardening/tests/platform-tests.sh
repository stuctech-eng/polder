#!/usr/bin/env bash
# Tests voor migraties 0026 (platformbeheer) en 0027 (platformacties) en de rollbacks (ALLEEN lokaal; maakt en verwijdert eigen kopie-databases).
# Gebruik:  PSQL="psql -X -q -h /socketdir -p 55432 -U postgres" BASIS=<database t/m 0025 met seed> bash platform-tests.sh
# BASIS bouw je met:  TOT=0025 DB=<naam> bash local-build.sh
set -uo pipefail
PSQL=${PSQL:-"psql -X -q"}; BASIS=${BASIS:?BASIS = database t/m 0025}
cd "$(dirname "$0")/../.."          # = supabase/
MIG=migrations/0026_platformbeheer.sql; RB=rollbacks/0026_rollback.sql
MIG7=migrations/0027_platform_acties.sql; RB7=rollbacks/0027_rollback.sql
pass=0; fail=0
ok()   { if [ "${2:-}" = "1" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
vers() { $PSQL -d postgres -c "drop database if exists pl_test" -c "create database pl_test template $BASIS" >/dev/null 2>&1; }
run()  { $PSQL -d pl_test -c "$(cat "$1")" 2>&1; }
sql()  { $PSQL -d pl_test -At -c "$1" 2>/dev/null; }
# vingerafdruk van alles wat 0026 raakt; een mislukte meting geeft een unieke waarde (nooit een vals "gelijk")
stand() { local v; v=$(sql "select md5(coalesce((select string_agg(c.relname||coalesce(array_to_string(c.relacl,','),'')||c.relrowsecurity::text, '|' order by c.relname)
  from pg_class c where c.relnamespace='public'::regnamespace and c.relname in ('platform_admins','platform_log')),'')
  || coalesce((select string_agg(p.proname||md5(p.prosrc)||coalesce(array_to_string(p.proacl,','),''), '|' order by p.proname) from pg_proc p
       where p.pronamespace='public'::regnamespace and (p.proname = 'is_platform_admin' or p.proname like 'platform\\_%')),'')
  || (select count(*)::text from pg_class where relnamespace='public'::regnamespace))" | tail -1)
  if [[ "$v" =~ ^[0-9a-f]{32}$ ]]; then echo "$v"; else echo "MEETFOUT-$RANDOM-$RANDOM"; fi; }

echo "== $($PSQL -d postgres -At -c 'show server_version')"
ok "blokken passen in de editor (< 3000 tekens)" $(for f in $MIG $RB $MIG7 $RB7; do [ "$(wc -c < $f)" -lt 3000 ] || exit; done; echo 1)

# 1. uitgangsstand 0025 -> migratie slaagt
vers; s0=$(stand); out=$(run $MIG); ok "migratie slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"
s1=$(stand)
ok "meting ziet de wijziging" $([ "$s0" != "$s1" ] && [[ "$s0" != MEETFOUT* ]] && echo 1)
ok "beheerderslijst leeg na de migratie" $([ "$(sql "select count(*) from public.platform_admins")" = "0" ] && echo 1)
# 2. tweede keer -> afbreken, niets gewijzigd
out=$(run $MIG); ok "tweede keer: afgebroken" $(echo "$out" | grep -q "0026 vooraf" && echo 1) "$out"
ok "tweede keer: niets gewijzigd" $([ "$(stand)" = "$s1" ] && echo 1)
# 3. rollback -> exact terug
out=$(run $RB); ok "rollback slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"
ok "rollback: alles exact als de uitgangsstand" $([ "$(stand)" = "$s0" ] && echo 1)
# 4. tweede rollback -> afbreken
out=$(run $RB); ok "tweede rollback: afgebroken" $(echo "$out" | grep -q "0026-rollback vooraf" && echo 1) "$out"
ok "tweede rollback: niets gewijzigd" $([ "$(stand)" = "$s0" ] && echo 1)
# 5. migratie na rollback slaagt opnieuw
out=$(run $MIG); ok "migratie na rollback slaagt opnieuw" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"
# 6. zonder 0025 (my_access afwijkend) -> migratie breekt af, niets gewijzigd
vers; sql "create or replace function public.my_access() returns text language sql stable security definer set search_path = public, pg_temp as \$\$ select 'ok'::text \$\$" >/dev/null
sa=$(stand); out=$(run $MIG); ok "afwijkende my_access: migratie breekt af" $(echo "$out" | grep -q "0026 vooraf" && echo 1) "$out"
ok "afwijkende my_access: niets gewijzigd" $([ "$(stand)" = "$sa" ] && echo 1)

# 7. 0027 op 0026: slaagt; tweede keer faalt zonder wijziging; 0026-rollback weigert zolang 0027 er is; 0027-rollback exact terug
vers; run $MIG >/dev/null; s6=$(stand)
out=$(run $MIG7); ok "0027 slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"; s7=$(stand)
ok "0027: meting ziet de wijziging" $([ "$s6" != "$s7" ] && [[ "$s6" != MEETFOUT* ]] && echo 1)
out=$(run $MIG7); ok "0027 tweede keer: afgebroken" $(echo "$out" | grep -qi "already exists" && echo 1) "$out"
ok "0027 tweede keer: niets gewijzigd" $([ "$(stand)" = "$s7" ] && echo 1)
out=$(run $RB); ok "0026-rollback met 0027 aanwezig: afgebroken" $(echo "$out" | grep -q "eerst 0027" && echo 1) "$out"
ok "0026-rollback met 0027 aanwezig: niets gewijzigd" $([ "$(stand)" = "$s7" ] && echo 1)
out=$(run $RB7); ok "0027-rollback slaagt, exact terug naar 0026" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s6" ] && echo 1) "$out"
out=$(run $RB7); ok "0027 tweede rollback: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0027-rollback vooraf" && [ "$(stand)" = "$s6" ] && echo 1) "$out"
# 8. 0027 zonder 0026: afgebroken, niets gewijzigd
vers; sb=$(stand); out=$(run $MIG7); ok "0027 zonder 0026: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0027 vooraf" && [ "$(stand)" = "$sb" ] && echo 1) "$out"

$PSQL -d postgres -c "drop database if exists pl_test" >/dev/null 2>&1
echo "RESULTAAT: $pass PASS, $fail FAIL"
[ $fail -eq 0 ]
