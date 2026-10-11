#!/usr/bin/env bash
# Tests voor migraties 0028-0030 (modules per restaurant) en de rollbacks (ALLEEN lokaal; maakt en verwijdert eigen kopie-databases).
# Gebruik:  PSQL="psql -X -q -h /socketdir -p 55432 -U postgres" BASIS=<database t/m 0027 met seed> bash modules-tests.sh
# BASIS bouw je met:  TOT=0027 DB=<naam> bash local-build.sh
set -uo pipefail
PSQL=${PSQL:-"psql -X -q"}; BASIS=${BASIS:?BASIS = database t/m 0027}
cd "$(dirname "$0")/../.."          # = supabase/
M8=migrations/0028_modules.sql; M9=migrations/0029_module_beheer.sql; M0=migrations/0030_module_wacht.sql
R8=rollbacks/0028_rollback.sql; R9=rollbacks/0029_rollback.sql; R0=rollbacks/0030_rollback.sql
RA="a0000000-0000-0000-0000-000000000001"; ORPH="c0000000-0000-0000-0000-000000000001"
pass=0; fail=0
ok()   { if [ "${2:-}" = "1" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
vers() { $PSQL -d postgres -c "drop database if exists md_test" -c "create database md_test template $BASIS" >/dev/null 2>&1; }
run()  { $PSQL -d md_test -c "$(cat "$1")" 2>&1; }
sql()  { $PSQL -d md_test -At -c "$1" 2>/dev/null; }
geldig() { if [[ "$1" =~ ^[0-9a-f]{32}$ ]]; then echo "$1"; else echo "MEETFOUT-$RANDOM-$RANDOM"; fi; }
# vingerafdruk van alles wat 0028-0030 raakt; een mislukte meting geeft een unieke waarde (nooit een vals "gelijk")
stand() { geldig "$(sql "select md5(
  coalesce((select string_agg(c.relname||coalesce(array_to_string(c.relacl,','),'')||c.relrowsecurity::text, '|' order by c.relname)
    from pg_class c where c.relnamespace='public'::regnamespace and c.relname in ('features','restaurant_features')),'')
  || coalesce((select string_agg(p.proname||md5(p.prosrc)||coalesce(array_to_string(p.proacl,','),''), '|' order by p.proname) from pg_proc p
    where p.pronamespace='public'::regnamespace and p.proname in ('feature_aan','my_feature','platform_module_zetten','module_wacht')),'')
  || coalesce((select string_agg(tgrelid::regclass::text, ',' order by 1) from pg_trigger where tgname = 'module_wacht'),'')
  || (select pg_get_constraintdef(oid) from pg_constraint where conname = 'platform_log_action_check')
  || (select count(*)::text from pg_class where relnamespace='public'::regnamespace))" | tail -1)"; }
# G1: alle BESTAANDE guard-/xref-functies en hun triggers (alles behalve module_wacht)
guards() { geldig "$(sql "select md5(coalesce((select string_agg(p.proname||md5(p.prosrc)||p.prosecdef::text, '|' order by p.proname) from pg_proc p
    where p.pronamespace='public'::regnamespace and p.prorettype = 'trigger'::regtype and p.proname <> 'module_wacht'),'')
  || coalesce((select string_agg(pg_get_triggerdef(t.oid), '|' order by 1) from pg_trigger t where not t.tgisinternal and t.tgname <> 'module_wacht'),''))" | tail -1)"; }

echo "== $($PSQL -d postgres -At -c 'show server_version')"
ok "6 blokken passen in de editor (< 3000 tekens)" $(for f in $M8 $M9 $M0 $R8 $R9 $R0; do [ "$(wc -c < $f)" -lt 3000 ] || exit; done; echo 1)

# 1. heen, elke stap afzonderlijk, met tweede keer = afgebroken zonder wijziging
vers; s0=$(stand); g0=$(guards)
out=$(run $M8); ok "0028 slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"; s8=$(stand)
ok "0028: meting ziet de wijziging" $([ "$s0" != "$s8" ] && [[ "$s0" != MEETFOUT* ]] && echo 1)
out=$(run $M8); ok "0028 tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0028 vooraf" && [ "$(stand)" = "$s8" ] && echo 1) "$out"
out=$(run $M9); ok "0029 slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"; s9=$(stand)
ok "0029: meting ziet de wijziging" $([ "$s8" != "$s9" ] && echo 1)
out=$(run $M9); ok "0029 tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0029 vooraf" && [ "$(stand)" = "$s9" ] && echo 1) "$out"
out=$(run $M0); ok "0030 slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"; s30=$(stand)
ok "0030: meting ziet de wijziging" $([ "$s9" != "$s30" ] && echo 1)
out=$(run $M0); ok "0030 tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0030 vooraf" && [ "$(stand)" = "$s30" ] && echo 1) "$out"
ok "G1: bestaande guards en triggers ongewijzigd na 0028-0030" $([ "$(guards)" = "$g0" ] && [[ "$g0" != MEETFOUT* ]] && echo 1)

# 2. rollbacks in de verkeerde volgorde: afgebroken, niets gewijzigd
out=$(run $R8); ok "0028-rollback met 0029/0030 aanwezig: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "eerst 0030 en 0029" && [ "$(stand)" = "$s30" ] && echo 1) "$out"
out=$(run $R9); ok "0029-rollback met 0030 aanwezig: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "eerst 0030" && [ "$(stand)" = "$s30" ] && echo 1) "$out"
# 3. rollbacks in de goede volgorde: telkens exact terug
out=$(run $R0); ok "0030-rollback: exact terug naar de stand na 0029" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s9" ] && echo 1) "$out"
out=$(run $R0); ok "0030 tweede rollback: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0030-rollback vooraf" && [ "$(stand)" = "$s9" ] && echo 1) "$out"
out=$(run $R9); ok "0029-rollback: exact terug naar de stand na 0028" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s8" ] && echo 1) "$out"
out=$(run $R8); ok "0028-rollback: exact terug naar 0027" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s0" ] && echo 1) "$out"
ok "G1: bestaande guards en triggers ongewijzigd na alle rollbacks" $([ "$(guards)" = "$g0" ] && echo 1)
out=$(run $M8)$(run $M9)$(run $M0); ok "0028-0030 na rollback opnieuw: slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s30" ] && echo 1) "$out"

# 4. rollbacks weigeren bij gegevens (geen stil verlies of stille heractivering)
sql "insert into platform_admins (user_id) values ('$ORPH')" >/dev/null
sql "select public.platform_module_zetten('$ORPH','$RA','approval',false)" >/dev/null
run $R0 >/dev/null; sm=$(stand)
out=$(run $R9); ok "0029-rollback met module-regels in het logboek: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "module-regels" && [ "$(stand)" = "$sm" ] && echo 1) "$out"
sql "set session_replication_role = replica; delete from platform_log where action like 'module_%'" >/dev/null; run $R9 >/dev/null; sm=$(stand)
out=$(run $R8); ok "0028-rollback met module-instelling: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "module-instellingen" && [ "$(stand)" = "$sm" ] && echo 1) "$out"

# 5. verkeerde uitgangsstand: afgebroken, niets gewijzigd
vers; sql "create or replace function public.platform_restaurant_status(p_admin uuid, p_restaurant uuid, p_aan boolean) returns boolean language sql as \$\$ select p_aan \$\$" >/dev/null
sa=$(stand); out=$(run $M8); ok "0028 op afwijkende 0027-functie: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0028 vooraf" && [ "$(stand)" = "$sa" ] && echo 1) "$out"
vers; sb=$(stand); out=$(run $M9); ok "0029 zonder 0028: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0029 vooraf" && [ "$(stand)" = "$sb" ] && echo 1) "$out"
out=$(run $M0); ok "0030 zonder 0028: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0030 vooraf" && [ "$(stand)" = "$sb" ] && echo 1) "$out"

$PSQL -d postgres -c "drop database if exists md_test" >/dev/null 2>&1
echo "RESULTAAT: $pass PASS, $fail FAIL"
[ $fail -eq 0 ]
