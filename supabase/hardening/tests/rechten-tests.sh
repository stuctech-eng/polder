#!/usr/bin/env bash
# Tests voor migratie 0036 (overbodige rechten), de rollback, het controleblok en bewust kapotte versies
# (ALLEEN lokaal; maakt en verwijdert eigen kopie-databases).
# Gebruik:  PSQL="psql -X -q -h /socketdir -p 55433 -U postgres" BASIS=<database> bash rechten-tests.sh
#   PostgreSQL 17: BASIS = productiestand, gebouwd met  TOT=0035 PRODSTAND=1 DB=<naam> bash local-build.sh
#   PostgreSQL 16: BASIS = t/m 0035 (geen MAINTAIN): alleen getoetst dat 0036 en de rollback afbreken zonder wijziging
set -uo pipefail
PSQL=${PSQL:-"psql -X -q"}; BASIS=${BASIS:?BASIS = database t/m 0035}
cd "$(dirname "$0")/../.."          # = supabase/
M=migrations/0036_overbodige_rechten.sql; R=rollbacks/0036_rollback.sql; C=hardening/prod-rechten-checks.sql
INV=hardening/prod-rechten-inventaris.sql; FIX=hardening/tests/prod-inventaris-13a.txt
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok()   { if [ "${2:-}" = "1" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
vers() { $PSQL -d postgres -c "drop database if exists rt_test" -c "create database rt_test template $BASIS" >/dev/null 2>&1; }
run()  { $PSQL -d rt_test -c "$(cat "$1")" 2>&1; }
sql()  { $PSQL -d rt_test -At -c "$1" 2>/dev/null; }
geldig() { if [[ "$1" =~ ^[0-9a-f]{32}$ ]]; then echo "$1"; else echo "MEETFOUT-$RANDOM-$RANDOM"; fi; }
# rechten als losse regels (grantor, rechthebbende, recht, doorgeefbaar), zodat de volgorde in de ACL niet uitmaakt
ACL="(select coalesce(string_agg(x.grantor::regrole || '>' || x.grantee::regrole || ':' || x.privilege_type || x.is_grantable::text, ','
       order by x.grantor::regrole::text collate \"C\", x.grantee::regrole::text collate \"C\", x.privilege_type collate \"C\"), '')
       from aclexplode(%s) x where %s)"
acl() { printf "$ACL" "$1" "${2:-true}"; }
# ALLES wat 0036 zou kunnen raken of juist niet mag raken. $1 = filter op rechthebbende (standaard: alles)
alles() { local w=${1:-true}; geldig "$(sql "select md5(
  coalesce((select string_agg(c.relname || c.relkind::text || c.relrowsecurity::text || $(acl c.relacl "$w"), '|' order by c.relname collate \"C\")
    from pg_class c where c.relnamespace = 'public'::regnamespace),'')
  || coalesce((select string_agg(c.relname || '.' || a.attname || $(acl a.attacl "$w"), '|' order by c.relname collate \"C\", a.attname collate \"C\")
    from pg_attribute a join pg_class c on c.oid = a.attrelid where c.relnamespace = 'public'::regnamespace and a.attacl is not null),'')
  || coalesce((select string_agg(d.defaclrole::regrole || d.defaclobjtype::text || d.defaclnamespace::regnamespace || $(acl d.defaclacl "$w"), '|'
    order by d.defaclrole::regrole::text collate \"C\", d.defaclobjtype::text collate \"C\", d.defaclnamespace::regnamespace::text collate \"C\")
    from pg_default_acl d),'')
  || coalesce((select string_agg(tablename || policyname || cmd || array_to_string(roles, ',') || coalesce(qual,'') || coalesce(with_check,''), '|'
    order by tablename collate \"C\", policyname collate \"C\") from pg_policies),'')
  || coalesce((select string_agg(n.nspname || '.' || p.proname || md5(p.prosrc) || p.prosecdef::text || $(acl p.proacl "$w"), '|'
    order by n.nspname collate \"C\", p.proname collate \"C\", md5(p.prosrc)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public','auth','storage','extensions')),'')
  || coalesce((select string_agg(pg_get_triggerdef(oid), '|' order by pg_get_triggerdef(oid) collate \"C\") from pg_trigger where not tgisinternal),'')
  || coalesce((select string_agg(nspname || $(acl nspacl "$w"), '|' order by nspname collate \"C\") from pg_namespace),''))" | tail -1)"; }
# alles behalve de rechten van authenticated en anon: moet door 0036 en de rollback ongemoeid blijven
# (de standaardrechten van postgres voor tabellen staan erin, met anon/authenticated eruit gefilterd)
rest() { alles "x.grantee::regrole::text not in ('authenticated','anon')"; }
dienst() { alles "x.grantee::regrole::text = 'service_role'"; }
admin() { geldig "$(sql "select md5(coalesce(string_agg(defaclobjtype::text || defaclacl::text, '|' order by defaclobjtype::text), ''))
  from pg_default_acl where defaclrole = 'supabase_admin'::regrole" | tail -1)"; }
inv()  { $PSQL -d rt_test -At -F'|' -f $INV 2>&1 | grep -v '^$' | LC_ALL=C sort; }
fixture() { grep -v '^#' $FIX; }
check() { $PSQL -d rt_test -At -F'|' -f $C 2>&1 | grep -v '^$' | head -1 | cut -d'|' -f1-5; }
lint() { sql "select count(*) from pg_class c, unnest('{SELECT,INSERT,UPDATE,DELETE}'::text[]) o
  where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname not like '\_%'
  and (case o when 'DELETE' then has_table_privilege('authenticated', c.oid, o) else has_any_column_privilege('authenticated', c.oid, o) end)
  <> exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname and p.cmd in (o, 'ALL')
             and p.roles && '{authenticated,public}')"; }
fails() { sql "select count(*) from hardening_test.run($1) where result = 'FAIL'"; }
faillijst() { sql "select coalesce(string_agg(id, ',' order by id), '') from hardening_test.run($1) where result = 'FAIL'"; }
# alleen de RR-cases: de PQ-cases (stap 14a) worden overgeslagen zolang 0037-0042 er niet zijn
skips() { sql "select coalesce(string_agg(id, ',' order by id), '') from hardening_test.run($1) where result = 'SKIP' and id like 'RR%'"; }
# een nieuwe tabel aanmaken als postgres (zoals een toekomstige migratie) en de rechten tonen die hij krijgt; daarna weer weg
nieuw() { $PSQL -d rt_test -At -c "begin; create table public.t13_proef (id int);
  select coalesce((select string_agg(x.grantee::regrole || ':' || x.privilege_type, ',' order by x.grantee::regrole::text, x.privilege_type)
    from pg_class c, aclexplode(c.relacl) x where c.oid = 'public.t13_proef'::regclass and x.grantee::regrole::text in ('anon','authenticated','service_role')), '')
    || '|rls=' || (select relrowsecurity from pg_class where oid = 'public.t13_proef'::regclass); rollback;" 2>&1 | grep -v '^$' | grep -v -i '^begin\|^rollback\|^create'; }
# als ingelogde medewerker (authenticated) een bewerking proberen; geeft OK of de foutmelding
als_auth() { $PSQL -d rt_test -At -c "begin; set local role authenticated; $1; rollback;" 2>&1 | grep -i -o 'permission denied[^"]*' | head -1 || true; }
mut()  { cp "$1" "$TMP/$2"; python3 - "$TMP/$2" "$3" "$4" <<'E'
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
assert s.count(old) == 1, "mutatie niet uniek: " + old
open(p, 'w').write(s.replace(old, new))
E
}

V=$($PSQL -d postgres -At -c 'show server_version_num'); echo "== PostgreSQL $($PSQL -d postgres -At -c 'show server_version')"
ok "3 blokken passen in de editor (< 3000 tekens)" $(for f in $M $R $C; do [ "$(wc -c < $f)" -lt 3000 ] || exit; done; echo 1)

if [ "$V" -lt 170000 ]; then
  vers; a0=$(alles)
  out=$(run $M); ok "PG16: 0036 breekt af (geen MAINTAIN, stand wijkt af), niets gewijzigd" $(echo "$out" | grep -q "0036 vooraf" && [ "$(alles)" = "$a0" ] && [[ "$a0" != MEETFOUT* ]] && echo 1) "$out"
  out=$(run $R); ok "PG16: rollback breekt af, niets gewijzigd" $(echo "$out" | grep -q "0036-rollback vooraf" && [ "$(alles)" = "$a0" ] && echo 1) "$out"
  ok "PG16: controleblok zegt ONBEKEND" $([ "$(check | cut -d'|' -f1)" = "ONBEKEND" ] && echo 1) "$(check)"
  echo "== $pass geslaagd, $fail mislukt"; $PSQL -d postgres -c "drop database if exists rt_test" >/dev/null 2>&1; [ $fail = 0 ]; exit
fi

# 1. uitgangsstand = gemeten productie
vers; a0=$(alles); r0=$(rest); d0=$(dienst); m0=$(admin)
ok "uitgangsstand: inventaris lokaal regel voor regel gelijk aan productie (13a)" $([ "$(inv)" = "$(fixture)" ] && echo 1) "$(diff <(fixture) <(inv))"
if [ "$(inv)" != "$(fixture)" ]; then echo "STOP: BASIS is niet de gemeten productiestand (bouw met PRODSTAND=1); verdere tests zeggen dan niets"; echo "== $pass geslaagd, $((fail)) mislukt"; exit 1; fi
ok "controleblok vooraf: voor 0036|34|25|t|0" $([ "$(check)" = "voor 0036|34|25|t|0" ] && echo 1) "$(check)"
ok "lint vooraf: 34 dode rechten" $([ "$(lint)" = "34" ] && echo 1) "$(lint)"
ok "uitgangsstand: harnas run(12) 0 FAIL" $([ "$(fails 12)" = "0" ] && echo 1)
S13=$(sql "select string_agg(id, ',' order by id) from hardening_test.cases where step = 13 and expect_after is distinct from expect_now")
ok "uitgangsstand: run(13) faalt precies op de stap-13-cases ($S13)" $([ -n "$S13" ] && [ "$(faillijst 13)" = "$S13" ] && echo 1) "$(faillijst 13)"
ok "nieuwe tabel vooraf: anon MAINTAIN, authenticated met MAINTAIN, RLS aan" $([ "$(nieuw)" = "anon:MAINTAIN,authenticated:DELETE,authenticated:INSERT,authenticated:MAINTAIN,authenticated:SELECT,authenticated:UPDATE,service_role:DELETE,service_role:INSERT,service_role:MAINTAIN,service_role:SELECT,service_role:UPDATE|rls=true" ] && echo 1) "$(nieuw)"
ok "vooraf: medewerker mag (dood recht) DELETE op contacts uitvoeren (RLS: 0 rijen)" $([ -z "$(als_auth 'delete from public.contacts')" ] && echo 1) "$(als_auth 'delete from public.contacts')"
out=$(run $R); ok "rollback zonder 0036: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0036-rollback vooraf" && [ "$(alles)" = "$a0" ] && [[ "$a0" != MEETFOUT* ]] && echo 1) "$out"

# 2. heen
out=$(run $M); ok "0036 slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"; a1=$(alles)
ok "0036: meting ziet de wijziging" $([ "$a1" != "$a0" ] && echo 1)
ok "controleblok na 0036: na 0036|0|0|f|0" $([ "$(check)" = "na 0036|0|0|f|0" ] && echo 1) "$(check)"
ok "lint na 0036: elk recht van authenticated heeft een policy en omgekeerd" $([ "$(lint)" = "0" ] && echo 1) "$(lint)"
ok "geen MAINTAIN meer voor authenticated of anon (tabellen)" $([ "$(sql "select count(*) from pg_class c, aclexplode(c.relacl) x where c.relnamespace='public'::regnamespace and x.grantee::regrole::text in ('anon','authenticated') and x.privilege_type='MAINTAIN'")" = "0" ] && echo 1)
ok "approval_settings: nog precies de 8 open kolommen leesbaar, PIN niet" $([ "$(sql "select count(*) from information_schema.column_privileges where table_schema='public' and table_name='approval_settings' and grantee='authenticated' and privilege_type='SELECT'")" = "8" ] && [ "$(sql "select has_column_privilege('authenticated','public.approval_settings','pin_hash','SELECT')")" = "f" ] && echo 1)
ok "service_role: alle rechten exact gelijk" $([ "$(dienst)" = "$d0" ] && [[ "$d0" != MEETFOUT* ]] && echo 1)
ok "standaardrechten supabase_admin exact gelijk" $([ "$(admin)" = "$m0" ] && [[ "$m0" != MEETFOUT* ]] && echo 1)
ok "al het andere (policies, functies, triggers, eigenaar- en dienstrechten, overige standaardrechten) exact gelijk" $([ "$(rest)" = "$r0" ] && [[ "$r0" != MEETFOUT* ]] && echo 1)
ok "standaardrechten postgres: tabellen zonder MAINTAIN voor anon/authenticated, sequences en functies gelijk" $([ "$(sql "select string_agg(defaclobjtype::text || '=' || array_to_string(defaclacl, ' '), ' ; ' order by defaclobjtype::text) from pg_default_acl where defaclrole='postgres'::regrole and defaclnamespace='public'::regnamespace")" = "S=postgres=rwU/postgres authenticated=rU/postgres service_role=rU/postgres ; f=postgres=X/postgres ; r=postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdm/postgres" ] && echo 1)
ok "nieuwe tabel na 0036: anon niets, authenticated zonder MAINTAIN, service_role gelijk, RLS aan" $([ "$(nieuw)" = "authenticated:DELETE,authenticated:INSERT,authenticated:SELECT,authenticated:UPDATE,service_role:DELETE,service_role:INSERT,service_role:MAINTAIN,service_role:SELECT,service_role:UPDATE|rls=true" ] && echo 1) "$(nieuw)"
ok "na 0036: medewerker krijgt 'permission denied' op DELETE contacts" $(als_auth 'delete from public.contacts' | grep -q 'permission denied' && echo 1)
ok "na 0036: medewerker krijgt 'permission denied' op UPDATE payments" $(als_auth 'update public.payments set amount = amount' | grep -q 'permission denied' && echo 1)
ok "na 0036: medewerker leest nog receipts en schrijft nog open_tabs (rechten met policy blijven)" $([ -z "$(als_auth 'select 1 from public.receipts limit 1; update public.open_tabs set status = status')" ] && echo 1) "$(als_auth 'select 1 from public.receipts limit 1; update public.open_tabs set status = status')"
ok "harnas run(13) 0 FAIL na 0036" $([ "$(fails 13)" = "0" ] && echo 1) "$(faillijst 13)"
ok "overgeslagen cases precies RR62c,RR62d,RR62i,RR62s,RR62u (email_settings bestaat niet, zoals productie)" $([ "$(skips 13)" = "RR62c,RR62d,RR62i,RR62s,RR62u" ] && echo 1) "$(skips 13)"
out=$(run $M); ok "0036 tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0036 vooraf" && [ "$(alles)" = "$a1" ] && echo 1) "$out"

# 3. terug
out=$(run $R); ok "rollback slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$(echo "$out" | head -3)"
ok "rollback: alles exact terug (ook standaardrechten en grantor)" $([ "$(alles)" = "$a0" ] && echo 1)
ok "rollback: inventaris weer regel voor regel gelijk aan productie" $([ "$(inv)" = "$(fixture)" ] && echo 1) "$(diff <(fixture) <(inv))"
ok "controleblok na rollback: voor 0036|34|25|t|0" $([ "$(check)" = "voor 0036|34|25|t|0" ] && echo 1) "$(check)"
ok "harnas run(12) 0 FAIL na rollback" $([ "$(fails 12)" = "0" ] && echo 1) "$(faillijst 12)"
out=$(run $R); ok "rollback tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0036-rollback vooraf" && [ "$(alles)" = "$a0" ] && echo 1) "$out"
out=$(run $M); ok "0036 opnieuw na rollback: slaagt, zelfde eindstand" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(alles)" = "$a1" ] && echo 1) "$out"

# 4. uitgangsstand wijkt af: 0036 moet afbreken zonder wijziging
afwijking() { vers; sql "$2" >/dev/null; local b=$(alles); local out=$(run $M)
  ok "afwijkende uitgangsstand ($1): 0036 afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0036 vooraf" && [ "$(alles)" = "$b" ] && [[ "$b" != MEETFOUT* ]] && echo 1) "$out"; }
afwijking "extra recht TRUNCATE op contacts" "grant truncate on public.contacts to authenticated"
afwijking "service_role mist MAINTAIN op receipts" "revoke maintain on public.receipts from service_role"
afwijking "PIN-kolom leesbaar" "grant select (pin_hash) on public.approval_settings to authenticated"
afwijking "anon heeft SELECT op users" "grant select on public.users to anon"
afwijking "standaardrecht postgres anders" "alter default privileges for role postgres in schema public grant references on tables to anon"
afwijking "standaardrecht supabase_admin anders" "alter default privileges for role supabase_admin in schema public revoke all on functions from anon"
afwijking "extra tabel met rechten" "create table public.extra13 (id int); grant select on public.extra13 to authenticated"
afwijking "recht op de sequence ontbreekt" "revoke usage on sequence public.platform_log_id_seq from authenticated"

# 5. bewust kapotte migratie/rollback: moeten falen en niets half achterlaten
kapot() { vers; [ -n "${3:-}" ] && run $M >/dev/null; local b=$(alles); local out=$($PSQL -d rt_test -c "$(cat "$TMP/$2")" 2>&1)
  ok "kapot: $1 -> afgebroken, niets gewijzigd" $(echo "$out" | grep -q "achteraf\|division by zero" && [ "$(alles)" = "$b" ] && [[ "$b" != MEETFOUT* ]] && echo 1) "$out"; }
mut $M m1.sql "revoke all on public.contacts, public.integration_plugins, public.notifications from authenticated;" "revoke all on public.integration_plugins, public.notifications from authenticated;"
kapot "0036 vergeet contacts" m1.sql
mut $M m2.sql "revoke all on sequence public.platform_log_id_seq from authenticated;" "revoke all on sequence public.platform_log_id_seq from authenticated; revoke insert on public.receipts from authenticated;"
kapot "0036 trekt ook INSERT op receipts in" m2.sql
mut $M m3.sql "in schema public revoke maintain on tables from anon, authenticated;" "in schema public revoke maintain on tables from anon;"
kapot "0036 laat MAINTAIN in standaardrechten voor authenticated staan" m3.sql
mut $M m4.sql "revoke all on sequence public.platform_log_id_seq from authenticated;" "revoke all on sequence public.platform_log_id_seq from authenticated; revoke maintain on public.users from service_role;"
kapot "0036 raakt service_role" m4.sql
# zonder de vingerafdruk achteraf moet de lint de vergeten tabel nog vangen
mut $M m5.sql "if f is distinct from 'afd46a8208fb2d9892202d4ce71b912e' or exists" "if exists"
python3 - "$TMP/m5.sql" <<'E'
import sys; p = sys.argv[1]; s = open(p).read()
old = "revoke all on public.contacts, public.integration_plugins, public.notifications from authenticated;"
assert s.count(old) == 1; open(p, 'w').write(s.replace(old, "revoke all on public.integration_plugins, public.notifications from authenticated;"))
E
kapot "0036 zonder vingerafdruk achteraf, vergeet contacts (lint vangt)" m5.sql
mut $M m6.sql "revoke all on public.contacts," "select 1/0; revoke all on public.contacts,"
kapot "0036 fout halverwege" m6.sql
mut $R r1.sql "grant select, usage on sequence public.platform_log_id_seq to authenticated;" ""
kapot "rollback vergeet de sequence" r1.sql na
mut $R r2.sql "grant maintain on tables to anon, authenticated;" "grant maintain on tables to authenticated;"
kapot "rollback vergeet anon in de standaardrechten" r2.sql na
mut $R r3.sql "grant select, usage on sequence" "select 1/0; grant select, usage on sequence"
kapot "rollback fout halverwege" r3.sql na
# het controleblok moet een afwijking als ONBEKEND tonen
vers; sql "grant truncate on public.contacts to authenticated" >/dev/null
ok "controleblok: afwijkende stand = ONBEKEND" $([ "$(check | cut -d'|' -f1)" = "ONBEKEND" ] && echo 1) "$(check)"

# 6. kolomrechten van anon en service_role: horen bij de vingerafdruk (attacl). Elke afwijking: ONBEKEND en afbreken, niets gewijzigd.
# kr <tabel> <kolom> <rol> <recht>: bestaat dat kolomrecht echt in attacl (bewijs dat de opzet gelukt is, geen tabelrecht)
kr() { echo "exists (select 1 from pg_attribute a, aclexplode(a.attacl) x where a.attrelid = 'public.$1'::regclass and a.attname = '$2'
  and x.grantee = '$3'::regrole and x.privilege_type = '$4')"; }
# kolom <naam> <opzet-SQL> <bewijs-SQL> <voor|na> <bestand> <verwachte melding>
kolom() { vers; [ "$4" = na ] && run $M >/dev/null; local z=$(alles)
  local e=$($PSQL -d rt_test -v ON_ERROR_STOP=1 -c "$2" 2>&1 | grep -i error); local p=$(sql "select $3"); local b=$(alles); local s=$(check | cut -d'|' -f1)
  local out=$(run $5)
  ok "kolomrecht $1 ($4 0036): opzet gelukt en gemeten, controleblok ONBEKEND, $(basename $5) afgebroken, niets gewijzigd" \
    $([ -z "$e" ] && [ "$p" = t ] && [ "$b" != "$z" ] && [ "$s" = ONBEKEND ] && echo "$out" | grep -q "$6" && [ "$(alles)" = "$b" ] \
      && [[ "$b" != MEETFOUT* ]] && [[ "$z" != MEETFOUT* ]] && echo 1) "fout=$e bewijs=$p controleblok=$s $out"; }
kolom "anon SELECT (full_name) op contacts" "grant select (full_name) on public.contacts to anon" "$(kr contacts full_name anon SELECT)" voor $M "0036 vooraf"
kolom "anon UPDATE (method) op approval_settings" "grant update (method) on public.approval_settings to anon" "$(kr approval_settings method anon UPDATE)" voor $M "0036 vooraf"
kolom "service_role REFERENCES (id) op receipts" "grant references (id) on public.receipts to service_role" "$(kr receipts id service_role REFERENCES)" voor $M "0036 vooraf"
kolom "service_role SELECT (key) op features" "grant select (key) on public.features to service_role" "$(kr features key service_role SELECT)" voor $M "0036 vooraf"
kolom "anon SELECT (full_name) op contacts" "grant select (full_name) on public.contacts to anon" "$(kr contacts full_name anon SELECT)" na $R "0036-rollback vooraf"
kolom "service_role UPDATE (id) op platform_log" "grant update (id) on public.platform_log to service_role" "$(kr platform_log id service_role UPDATE)" na $R "0036-rollback vooraf"
# kapotte migratie die zelf een kolomrecht toekent: nacontrole faalt, alles teruggedraaid (ook dat kolomrecht)
mut $M k1.sql "revoke all on sequence public.platform_log_id_seq from authenticated;" "revoke all on sequence public.platform_log_id_seq from authenticated; grant select (full_name) on public.contacts to anon;"
kapot "0036 geeft anon kolomrecht SELECT (full_name) op contacts" k1.sql
ok "  en dat kolomrecht bestaat daarna niet" $([ "$(sql "select $(kr contacts full_name anon SELECT)")" = "f" ] && echo 1)
mut $M k2.sql "revoke all on sequence public.platform_log_id_seq from authenticated;" "revoke all on sequence public.platform_log_id_seq from authenticated; grant update (method) on public.approval_settings to service_role;"
kapot "0036 geeft service_role kolomrecht UPDATE (method) op approval_settings" k2.sql
ok "  en dat kolomrecht bestaat daarna niet" $([ "$(sql "select $(kr approval_settings method service_role UPDATE)")" = "f" ] && echo 1)
# normale stand: herkend als voor 0036, na 0036 en na rollback weer voor 0036; geen kolomrechten van anon/service_role
vers
ok "normale stand: geen enkel kolomrecht van anon of service_role" $([ "$(sql "select count(*) from pg_class c, pg_attribute a, aclexplode(a.attacl) x where a.attrelid = c.oid and c.relnamespace = 'public'::regnamespace and x.grantee::regrole::text in ('anon','service_role')")" = "0" ] && echo 1)
ok "normale stand: controleblok voor 0036 -> na 0036 -> (rollback) voor 0036" $([ "$(check | cut -d'|' -f1)" = "voor 0036" ] && [ -z "$(run $M | grep -i error)" ] \
  && [ "$(check | cut -d'|' -f1)" = "na 0036" ] && [ -z "$(run $R | grep -i error)" ] && [ "$(check | cut -d'|' -f1)" = "voor 0036" ] && echo 1)

echo "== $pass geslaagd, $fail mislukt"
$PSQL -d postgres -c "drop database if exists rt_test" >/dev/null 2>&1
[ $fail = 0 ]
