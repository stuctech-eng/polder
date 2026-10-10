#!/usr/bin/env bash
# Tests voor migratie 0025 (restaurant aan/uit) en de rollback (ALLEEN lokaal; maakt en verwijdert eigen kopie-databases).
# Gebruik:  PSQL="psql -X -q -h /socketdir -p 55432 -U postgres" BASIS=<database t/m 0024 met seed> bash aanuit-tests.sh
# BASIS bouw je met:  TOT=0024 DB=<naam> bash local-build.sh
set -uo pipefail
PSQL=${PSQL:-"psql -X -q"}; BASIS=${BASIS:?BASIS = database t/m 0024}
cd "$(dirname "$0")/../.."          # = supabase/
MIG=migrations/0025_restaurant_aan_uit.sql; RB=rollbacks/0025_rollback.sql
RA="a0000000-0000-0000-0000-000000000001"
pass=0; fail=0
ok()   { if [ "${2:-}" = "1" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
vers() { $PSQL -d postgres -c "drop database if exists au_test" -c "create database au_test template $BASIS" >/dev/null 2>&1; }
# zoals de Supabase-editor: het hele bestand als één opdracht
run()  { $PSQL -d au_test -c "$(cat "$1")" 2>&1; }
sql()  { $PSQL -d au_test -At -c "$1" 2>/dev/null; }
# vingerafdruk van alles wat 0025 raakt; een mislukte meting geeft een unieke waarde (nooit een vals "gelijk")
stand() { local v; v=$(sql "select md5(coalesce(string_agg(p.proname||md5(p.prosrc)||p.prosecdef::text||coalesce(array_to_string(p.proconfig,','),'')||coalesce(array_to_string(p.proacl,','),''), '|' order by p.proname),'')
  || (select count(*)::text from information_schema.columns where table_schema='public' and table_name='restaurants' and column_name='is_active')
  || (select coalesce(string_agg(to_jsonb(r)::text, ',' order by r.id), '') from public.restaurants r))
  from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('my_restaurant_id','my_role','my_access')" | tail -1)
  if [[ "$v" =~ ^[0-9a-f]{32}$ ]]; then echo "$v"; else echo "MEETFOUT-$RANDOM-$RANDOM"; fi; }
fp() { sql "select md5(btrim(regexp_replace(prosrc,'\s+',' ','g'))) from pg_proc where oid=to_regprocedure('public.$1()')"; }

echo "== $($PSQL -d postgres -At -c 'show server_version')"
ok "blokken passen in de editor (< 3000 tekens)" $([ "$(wc -c < $MIG)" -lt 3000 ] && [ "$(wc -c < $RB)" -lt 3000 ] && echo 1)

# 1. uitgangsstand -> migratie slaagt
vers; s0=$(stand); out=$(run $MIG); ok "migratie slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"
s1=$(stand)
ok "meting ziet de wijziging" $([ "$s0" != "$s1" ] && [[ "$s0" != MEETFOUT* ]] && echo 1)
ok "alle restaurants staan aan na de migratie" $([ "$(sql "select count(*) from public.restaurants where not is_active")" = "0" ] && echo 1)
ok "my_access() bestaat, SECURITY DEFINER" $([ "$(sql "select prosecdef from pg_proc where oid=to_regprocedure('public.my_access()')")" = "t" ] && echo 1)
# 2. tweede keer -> afbreken, niets gewijzigd
out=$(run $MIG); ok "tweede keer: afgebroken" $(echo "$out" | grep -q "0025 vooraf" && echo 1) "$out"
ok "tweede keer: niets gewijzigd" $([ "$(stand)" = "$s1" ] && echo 1)
# 3. rollback met een restaurant uit -> afbreken, niets gewijzigd (geen stille heractivering)
sql "update public.restaurants set is_active = false where id = '$RA'" >/dev/null; su=$(stand)
out=$(run $RB); ok "rollback met restaurant uit: afgebroken" $(echo "$out" | grep -q "restaurant uit" && echo 1) "$out"
ok "rollback met restaurant uit: niets gewijzigd, A staat nog uit" $([ "$(stand)" = "$su" ] && [ "$(sql "select is_active from public.restaurants where id='$RA'")" = "f" ] && echo 1)
sql "update public.restaurants set is_active = true where id = '$RA'" >/dev/null
# 4. rollback -> exact terug naar 0015
out=$(run $RB); ok "rollback slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"
ok "rollback: alles exact als de uitgangsstand" $([ "$(stand)" = "$s0" ] && echo 1)
ok "rollback: functies = 0015" $([ "$(fp my_restaurant_id)" = "dd3c18c75a9cbebfcd720d59059c5915" ] && [ "$(fp my_role)" = "f41f0b9bc00f23f62258cd703aad7844" ] && echo 1)
# 5. tweede rollback -> afbreken
out=$(run $RB); ok "tweede rollback: afgebroken" $(echo "$out" | grep -q "0025-rollback vooraf" && echo 1) "$out"
ok "tweede rollback: niets gewijzigd" $([ "$(stand)" = "$s0" ] && echo 1)
# 6. migratie na rollback slaagt opnieuw
out=$(run $MIG); ok "migratie na rollback slaagt opnieuw" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"

# 7. afwijkende uitgangsstand (my_role handmatig gewijzigd) -> migratie breekt af, niets gewijzigd
vers; sql "create or replace function public.my_role() returns text language sql stable security definer set search_path = public, pg_temp as \$\$ select u.role from public.users u where u.id = auth.uid() \$\$" >/dev/null
sa=$(stand); out=$(run $MIG); ok "afwijkende functie: migratie breekt af" $(echo "$out" | grep -q "0025 vooraf" && echo 1) "$out"
ok "afwijkende functie: niets gewijzigd" $([ "$(stand)" = "$sa" ] && echo 1)
# 8. afwijkende 0025-stand (my_access gewijzigd) -> rollback breekt af, niets gewijzigd
vers; run $MIG >/dev/null
sql "create or replace function public.my_access() returns text language sql stable security definer set search_path = public, pg_temp as \$\$ select 'ok'::text \$\$" >/dev/null
sb=$(stand); out=$(run $RB); ok "afwijkende my_access: rollback breekt af" $(echo "$out" | grep -q "0025-rollback vooraf" && echo 1) "$out"
ok "afwijkende my_access: niets gewijzigd" $([ "$(stand)" = "$sb" ] && echo 1)

$PSQL -d postgres -c "drop database if exists au_test" >/dev/null 2>&1
echo "RESULTAAT: $pass PASS, $fail FAIL"
[ $fail -eq 0 ]
