#!/usr/bin/env bash
# Tests voor migratie 0024 en de rollback (ALLEEN lokaal; maakt en verwijdert eigen kopie-databases).
# Gebruik:  PSQL="psql -X -q -h /socketdir -p 55432 -U postgres" BASIS=<database t/m 0022 met seed> bash tenantswitch-tests.sh
# BASIS bouw je met:  TOT=0022 DB=<naam> bash local-build.sh
set -uo pipefail
PSQL=${PSQL:-"psql -X -q"}; BASIS=${BASIS:?BASIS = database t/m 0022}
cd "$(dirname "$0")/../.."          # = supabase/
MIG=migrations/0024_tenantswitch_inline_policies.sql; RB=rollbacks/0024_rollback.sql
pass=0; fail=0
ok()   { if [ "$2" = "1" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
vers() { $PSQL -d postgres -c "drop database if exists ts_test" -c "create database ts_test template $BASIS" >/dev/null 2>&1; }
run()  { $PSQL -d ts_test -v ON_ERROR_STOP=1 -f "$1" 2>&1; }
# vingerafdruk van alle policies (naam, cmd, rollen, with check, tekst) -> om "niets gewijzigd" te bewijzen
# een lege of mislukte meting levert een unieke waarde op, zodat "niets gewijzigd" dan nooit vals PASS geeft
stand() { local v; v=$($PSQL -d ts_test -At -c "set search_path = ''; select md5(string_agg(c.relname::text||p.polname::text||p.polcmd::text||p.polroles::text||coalesce(pg_get_expr(p.polwithcheck,p.polrelid),'')||coalesce(pg_get_expr(p.polqual,p.polrelid),''), '|' order by c.relname, p.polname)) from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'public'::regnamespace" 2>/dev/null | tail -1)
          if [[ "$v" =~ ^[0-9a-f]{32}$ ]]; then echo "$v"; else echo "MEETFOUT-$RANDOM-$RANDOM"; fi; }
inline() { $PSQL -d ts_test -At -c "select count(*) from pg_policies where schemaname='public' and qual ~* 'from users' and tablename <> 'email_settings'"; }

echo "== $($PSQL -d postgres -At -c 'show server_version')"

# 1. uitgangsstand -> migratie slaagt, 0 oude controles over
vers; s0=$(stand); out=$(run $MIG); ok "migratie slaagt" $([ $? -eq 0 ] && echo 1) "$out"
ok "na migratie 0 van de 15 met de oude controle" $([ "$(inline)" = "0" ] && echo 1) "$(inline)"
s1=$(stand)
ok "meting ziet de wijziging (vingerafdruk voor en na verschilt)" $([ "$s0" != "$s1" ] && [[ "$s0" != MEETFOUT* ]] && echo 1)
# 2. tweede keer -> afbreken, niets gewijzigd
out=$(run $MIG); ok "tweede keer: afgebroken 'al uitgevoerd'" $(echo "$out" | grep -q "al uitgevoerd" && echo 1) "$out"
ok "tweede keer: niets gewijzigd" $([ "$(stand)" = "$s1" ] && echo 1)
# 3. rollback -> exact terug naar de uitgangsstand; tweede rollback breekt af
out=$(run $RB); ok "rollback slaagt" $([ $? -eq 0 ] && echo 1) "$out"
ok "rollback: alle policies exact als in de uitgangsstand" $([ "$(stand)" = "$s0" ] && echo 1)
out=$(run $RB); ok "tweede rollback: afgebroken" $(echo "$out" | grep -q "niet alle policies staan exact" && echo 1) "$out"
ok "tweede rollback: niets gewijzigd" $([ "$(stand)" = "$s0" ] && echo 1)
# 4. migratie na rollback slaagt weer
out=$(run $MIG); ok "migratie na rollback slaagt opnieuw" $([ $? -eq 0 ] && [ "$(stand)" = "$s1" ] && echo 1) "$out"

# 5. gemengde stand: één policy terug naar oud -> migratie én rollback breken af, niets gewijzigd
vers; run $MIG >/dev/null
$PSQL -d ts_test -c "alter policy \"tenant isolation payments\" on public.payments using (invoice_id in (select i.id from invoices i where i.restaurant_id in (select restaurant_id from users where users.id = auth.uid())))" >/dev/null
sm=$(stand)
out=$(run $MIG); ok "mengvorm: migratie breekt af" $(echo "$out" | grep -q "gemengde stand" && echo 1) "$out"
out=$(run $RB);  ok "mengvorm: rollback breekt af en noemt payments" $(echo "$out" | grep -q "payments" && echo 1) "$out"
ok "mengvorm: niets gewijzigd" $([ "$(stand)" = "$sm" ] && echo 1)

# 6. extra policy op een van de 15 -> migratie breekt af
vers; $PSQL -d ts_test -c "create policy extra on public.contacts for select using (true)" >/dev/null; se=$(stand)
out=$(run $MIG); ok "extra policy: migratie breekt af" $(echo "$out" | grep -q "niet precies 1 policy" && echo 1) "$out"
ok "extra policy: niets gewijzigd" $([ "$(stand)" = "$se" ] && echo 1)

# 7. onbekende tekst (bijv. handmatig aangepast in productie) -> migratie breekt af
vers; $PSQL -d ts_test -c "alter policy \"tenant isolation companies\" on public.companies using (restaurant_id in (select u.restaurant_id from users u where u.id = auth.uid()))" >/dev/null; su=$(stand)
out=$(run $MIG); ok "onbekende tekst: migratie breekt af" $(echo "$out" | grep -q "onbekende tekst" && echo 1) "$out"
ok "onbekende tekst: niets gewijzigd" $([ "$(stand)" = "$su" ] && echo 1)

# 8. nacontrole werkt: een migratie met een fout in één ALTER (= i.p.v. <>) breekt af, niets gewijzigd
vers; s0=$(stand); fout=$(mktemp)
sed 's/i.restaurant_id = public.my_restaurant_id()));$/i.restaurant_id <> public.my_restaurant_id()));/' $MIG > "$fout"
ok "foutvariant echt aangebracht in kopie van de migratie" $([ "$(grep -c '<> public.my_restaurant_id' "$fout")" -ge 1 ] && echo 1)
out=$(run "$fout"); ok "nacontrole: foute uitdrukking -> afgebroken" $(echo "$out" | grep -q "achteraf" && echo 1) "$out"
ok "nacontrole: niets gewijzigd" $([ "$(stand)" = "$s0" ] && echo 1); rm -f "$fout"

# 9. tabel bezet -> lock_timeout breekt af, niets gewijzigd
vers; s0=$(stand)
( $PSQL -d ts_test -c "begin; lock table public.invoices in access exclusive mode; select pg_sleep(12); commit;" >/dev/null 2>&1 & )
sleep 2; out=$(run $MIG); ok "bezette tabel: afgebroken op lock_timeout" $(echo "$out" | grep -q "lock timeout" && echo 1) "$out"
sleep 11; ok "bezette tabel: niets gewijzigd" $([ "$(stand)" = "$s0" ] && echo 1)

$PSQL -d postgres -c "drop database if exists ts_test" >/dev/null 2>&1
echo "RESULTAAT: $pass PASS, $fail FAIL"
[ $fail -eq 0 ]
