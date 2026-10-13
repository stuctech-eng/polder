#!/usr/bin/env bash
# Tests voor migratie 0035 (PIN-kolommen afschermen), de rollback en bewust kapotte versies (ALLEEN lokaal; eigen kopie-databases).
# Gebruik:  PSQL="psql -X -q -h /socketdir -p 55432 -U postgres" BASIS=<database t/m 0034 met seed en harnas> bash pin-tests.sh
# BASIS bouw je met:  TOT=0034 DB=<naam> bash local-build.sh
set -uo pipefail
PSQL=${PSQL:-"psql -X -q"}; BASIS=${BASIS:?BASIS = database t/m 0034}
cd "$(dirname "$0")/../.."          # = supabase/
M=migrations/0035_pin_kolommen.sql; R=rollbacks/0035_rollback.sql
pass=0; fail=0
ok()   { if [ "${2:-}" = "1" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
vers() { $PSQL -d postgres -c "drop database if exists pk_test" -c "create database pk_test template $BASIS" >/dev/null 2>&1; }
run()  { $PSQL -d pk_test -c "$(cat "$1")" 2>&1; }
sql()  { $PSQL -d pk_test -At -c "$1" 2>/dev/null; }
geldig() { if [[ "$1" =~ ^[0-9a-f]{32}$ ]]; then echo "$1"; else echo "MEETFOUT-$RANDOM-$RANDOM"; fi; }
# rechten op approval_settings: tabel-ACL + kolomrechten
stand() { geldig "$(sql "select md5(coalesce((select array_to_string(relacl, ',') from pg_class where oid = 'public.approval_settings'::regclass),'')
  || coalesce((select string_agg(grantee||column_name||privilege_type, '|' order by 1) from information_schema.column_privileges
     where table_schema='public' and table_name='approval_settings' and grantee in ('authenticated','anon','service_role')),''))" | tail -1)"; }
# alles wat NIET mag veranderen: rechten op alle andere tabellen, alle policies, alle triggerfuncties, module-stand
rest() { geldig "$(sql "select md5(coalesce((select string_agg(relname||coalesce(array_to_string(relacl, ','),''), '|' order by relname) from pg_class
    where relnamespace='public'::regnamespace and relkind='r' and relname <> 'approval_settings'),'')
  || coalesce((select string_agg(tablename||policyname||cmd||coalesce(qual,'')||coalesce(with_check,''), '|' order by tablename, policyname) from pg_policies where schemaname='public'),'')
  || coalesce((select string_agg(proname||md5(prosrc), '|' order by proname) from pg_proc where pronamespace='public'::regnamespace and prorettype='trigger'::regtype),'')
  || coalesce((select string_agg(r.id||k||public.feature_aan(r.id,k)::text, '|' order by r.id, k) from public.restaurants r
    cross join (values ('daily_closing'),('payment_registration'),('approval')) v(k)),''))" | tail -1)"; }
fails() { sql "select count(*) from hardening_test.run($1) where result = 'FAIL'"; }

echo "== $($PSQL -d postgres -At -c 'show server_version')"
ok "2 blokken passen in de editor (< 3000 tekens)" $(for f in $M $R; do [ "$(wc -c < $f)" -lt 3000 ] || exit; done; echo 1)

acl() { sql "select relacl::text || ' | anon-kolommen met SELECT: ' || (select count(*) from information_schema.columns x where x.table_schema='public' and x.table_name='approval_settings' and has_column_privilege('anon','public.approval_settings',x.column_name,'SELECT'))
  || ' | authenticated-kolommen met SELECT: ' || (select count(*) from information_schema.columns x where x.table_schema='public' and x.table_name='approval_settings' and has_column_privilege('authenticated','public.approval_settings',x.column_name,'SELECT'))
  from pg_class where oid='public.approval_settings'::regclass"; }
# 1. heen en terug
vers; s0=$(stand); r0=$(rest)
echo "== uitgangsrechten (0034): $(acl)"
ok "uitgangsstand: harnas run(11) 0 FAIL" $([ "$(fails 11)" = "0" ] && echo 1)
out=$(run $R); ok "rollback zonder 0035: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0035-rollback vooraf" && [ "$(stand)" = "$s0" ] && echo 1) "$out"
out=$(run $M); ok "0035 slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"; s1=$(stand)
echo "== rechten na 0035: $(acl)"
ok "0035: meting ziet de wijziging" $([ "$s0" != "$s1" ] && [[ "$s0" != MEETFOUT* ]] && echo 1)
out=$(run $M); ok "0035 tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0035 vooraf" && [ "$(stand)" = "$s1" ] && echo 1) "$out"
ok "harnas run(12) 0 FAIL na 0035" $([ "$(fails 12)" = "0" ] && echo 1)
ok "rechten op andere tabellen, policies, triggerfuncties en modules ongewijzigd" $([ "$(rest)" = "$r0" ] && [[ "$r0" != MEETFOUT* ]] && echo 1)
out=$(run $R); ok "rollback: exact terug naar 0034 (tabel-ACL en kolomrechten)" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s0" ] && echo 1) "$out"
echo "== rechten na rollback: $(acl)"
out=$(run $R); ok "rollback tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0035-rollback vooraf" && [ "$(stand)" = "$s0" ] && echo 1) "$out"
ok "na rollback: harnas run(11) 0 FAIL (oude stand, ook het oude lek)" $([ "$(fails 11)" = "0" ] && echo 1)
out=$(run $M); ok "0035 na rollback opnieuw: slaagt, zelfde stand" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s1" ] && echo 1) "$out"

# 2. afwijkende uitgangsstand: afgebroken, niets gewijzigd
vers; sql "alter table public.approval_settings add column proef text" >/dev/null; sa=$(stand)
out=$(run $M); ok "0035 met een onbekende extra kolom: afgebroken (geen kolom ongemerkt open of dicht)" $(echo "$out" | grep -q "0035 vooraf" && [ "$(stand)" = "$sa" ] && echo 1) "$out"
vers; sql "grant select on public.approval_settings to anon" >/dev/null; sa=$(stand)
out=$(run $M); ok "0035 als anon onverwacht SELECT heeft: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0035 vooraf" && [ "$(stand)" = "$sa" ] && echo 1) "$out"
# de policy "approval_settings select" bestaat alleen op een ANDERE tabel: 0035 moet afbreken
vers; sql "drop policy \"approval_settings select\" on public.approval_settings" >/dev/null
sql "create policy \"approval_settings select\" on public.companies for select to authenticated using (false)" >/dev/null; sa=$(stand)
ok "opzet: policy-naam alleen op companies, niet op approval_settings" $([ "$(sql "select string_agg(tablename, ',') from pg_policies where policyname = 'approval_settings select'")" = "companies" ] && echo 1)
out=$(run $M); ok "0035 als de select-policy alleen op een andere tabel staat: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0035 vooraf" && [ "$(stand)" = "$sa" ] && echo 1) "$out"
# service_role mist leesrecht op pin_salt (zonder dat de servercontrole werkt): 0035 moet afbreken
vers; sql "revoke select on public.approval_settings from service_role" >/dev/null
sql "grant select (auto_lock,company_id,created_at,id,is_required,method,notify_email,pin_hash,updated_at) on public.approval_settings to service_role" >/dev/null; sa=$(stand)
ok "opzet: service_role leest pin_salt niet, pin_hash wel" $([ "$(sql "select has_column_privilege('service_role','public.approval_settings','pin_salt','SELECT')::text || has_column_privilege('service_role','public.approval_settings','pin_hash','SELECT')::text")" = "falsetrue" ] && echo 1)
out=$(run $M); ok "0035 als service_role pin_salt niet kan lezen: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0035 vooraf" && [ "$(stand)" = "$sa" ] && echo 1) "$out"
vers; sql "grant select (pin_hash) on public.approval_settings to anon" >/dev/null; sa=$(stand)
out=$(run $M); ok "0035 als anon alleen pin_hash mag lezen (kolomrecht): afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0035 vooraf" && [ "$(stand)" = "$sa" ] && echo 1) "$out"
vers; run $M >/dev/null; sql "grant select (method) on public.approval_settings to anon" >/dev/null; sa=$(stand)
out=$(run $R); ok "rollback als anon onverwacht SELECT heeft: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0035-rollback vooraf" && [ "$(stand)" = "$sa" ] && echo 1) "$out"
vers; run $M >/dev/null; sql "grant select (pin_salt) on public.approval_settings to authenticated" >/dev/null; sa=$(stand)
out=$(run $R); ok "rollback als een PIN-kolom toch leesbaar is: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0035-rollback vooraf" && [ "$(stand)" = "$sa" ] && echo 1) "$out"

# 3. bewust kapotte versies en toevoegingen: het harnas moet ze vangen (run(12) > 0 FAIL)
mutant() {  # $1 naam, $2 oud, $3 nieuw
  local m=/tmp/pk_mut.sql
  python3 -c "import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[2])>=1; open(sys.argv[4],'w').write(s.replace(sys.argv[2], sys.argv[3]))" "$M" "$2" "$3" "$m" \
    || { ok "mutatie $1: tekst gevonden" 0; return; }
  vers; local out; out=$(run $m); local n; n=$(fails 12)
  ok "mutatie $1: gevangen ($n FAIL)" $([ -z "$(echo "$out" | grep -i error)" ] && [ "${n:-0}" -gt 0 ] && echo 1) "$out"
}
extra() {  # $1 naam, $2 sql na de echte migratie
  vers; local out; out=$(run $M)$($PSQL -d pk_test -c "$2" 2>&1); local n; n=$(fails 12)
  ok "mutatie $1: gevangen ($n FAIL)" $([ -z "$(echo "$out" | grep -i error)" ] && [ "${n:-0}" -gt 0 ] && echo 1) "$out"
}
extra "grant met pin_hash erbij" "grant select (pin_hash) on public.approval_settings to authenticated"
extra "tabel-SELECT weer terug" "grant select on public.approval_settings to authenticated"
extra "anon leest de methode" "grant select (method) on public.approval_settings to anon"
extra "service_role verliest pin_hash (server-controle breekt)" "revoke select on public.approval_settings from service_role"
extra "schrijven kapot (UPDATE weg)" "revoke update on public.approval_settings from authenticated"
mutant "te weinig open kolommen (notify_email vergeten)" "declare k text := 'auto_lock,company_id,created_at,id,is_required,method,notify_email,updated_at';" "declare k text := 'auto_lock,company_id,created_at,id,is_required,method,updated_at';"
$PSQL -d postgres -c "drop database if exists pk_test" >/dev/null 2>&1; rm -f /tmp/pk_mut.sql
echo "RESULTAAT: $pass PASS, $fail FAIL"
[ $fail -eq 0 ]
