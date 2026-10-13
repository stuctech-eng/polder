#!/usr/bin/env bash
# Tests voor migraties 0031-0032 (rolrechten facturen, factuurwacht), de rollbacks en bewust kapotte versies (ALLEEN lokaal).
# Gebruik:  PSQL="psql -X -q -h /socketdir -p 55432 -U postgres" BASIS=<database t/m 0030 met seed en harnas> bash facturen-tests.sh
# BASIS bouw je met:  TOT=0030 DB=<naam> bash local-build.sh
set -uo pipefail
PSQL=${PSQL:-"psql -X -q"}; BASIS=${BASIS:?BASIS = database t/m 0030}
cd "$(dirname "$0")/../.."          # = supabase/
M1=migrations/0031_rolrechten_facturen.sql; M2=migrations/0032_factuur_wacht.sql
R1=rollbacks/0031_rollback.sql; R2=rollbacks/0032_rollback.sql
pass=0; fail=0
ok()   { if [ "${2:-}" = "1" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
vers() { $PSQL -d postgres -c "drop database if exists fa_test" -c "create database fa_test template $BASIS" >/dev/null 2>&1; }
run()  { $PSQL -d fa_test -c "$(cat "$1")" 2>&1; }
sql()  { $PSQL -d fa_test -At -c "$1" 2>/dev/null; }
geldig() { if [[ "$1" =~ ^[0-9a-f]{32}$ ]]; then echo "$1"; else echo "MEETFOUT-$RANDOM-$RANDOM"; fi; }
# vingerafdruk van alles wat 0031-0032 raakt: policies en triggers op de 4 tabellen, de wachtfuncties
stand() { geldig "$(sql "select md5(
  coalesce((select string_agg(tablename||policyname||cmd||array_to_string(roles,',')||coalesce(qual,'')||coalesce(with_check,''), '|' order by tablename, policyname)
    from pg_policies where schemaname='public' and tablename in ('invoices','invoice_lines','payments','documents')),'')
  || coalesce((select string_agg(pg_get_triggerdef(oid), '|' order by 1) from pg_trigger where not tgisinternal
    and tgrelid in ('public.invoices'::regclass,'public.invoice_lines'::regclass,'public.payments'::regclass,'public.documents'::regclass)),'')
  || coalesce((select string_agg(proname||md5(prosrc), '|' order by proname) from pg_proc where pronamespace='public'::regnamespace
    and proname in ('invoices_guard','invoice_child_guard')),''))" | tail -1)"; }
# bestaande trigger-functies (alles behalve de twee nieuwe) en de module-instellingen: moeten altijd gelijk blijven
rest() { geldig "$(sql "select md5(coalesce((select string_agg(proname||md5(prosrc)||prosecdef::text, '|' order by proname) from pg_proc
    where pronamespace='public'::regnamespace and prorettype='trigger'::regtype and proname not in ('invoices_guard','invoice_child_guard')),'')
  || coalesce((select string_agg(r.id||k||public.feature_aan(r.id,k)::text, '|' order by r.id, k) from public.restaurants r
    cross join (values ('daily_closing'),('payment_registration'),('approval')) v(k)),''))" | tail -1)"; }
fails() { sql "select count(*) from hardening_test.run($1) where result = 'FAIL'"; }

echo "== $($PSQL -d postgres -At -c 'show server_version')"
ok "4 blokken passen in de editor (< 3000 tekens)" $(for f in $M1 $M2 $R1 $R2; do [ "$(wc -c < $f)" -lt 3000 ] || exit; done; echo 1)

# 1. heen, met tweede keer = afgebroken zonder wijziging
vers; s0=$(stand); r0=$(rest)
ok "uitgangsstand: harnas run(9) 0 FAIL" $([ "$(fails 9)" = "0" ] && echo 1)
out=$(run $M2); ok "0032 zonder 0031: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0032 vooraf" && [ "$(stand)" = "$s0" ] && echo 1) "$out"
out=$(run $R1); ok "0031-rollback zonder 0031: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0031-rollback vooraf" && [ "$(stand)" = "$s0" ] && echo 1) "$out"
out=$(run $M1); ok "0031 slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"; s1=$(stand)
ok "0031: meting ziet de wijziging" $([ "$s0" != "$s1" ] && [[ "$s0" != MEETFOUT* ]] && echo 1)
out=$(run $M1); ok "0031 tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0031 vooraf" && [ "$(stand)" = "$s1" ] && echo 1) "$out"
out=$(run $M2); ok "0032 slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"; s2=$(stand)
ok "0032: meting ziet de wijziging" $([ "$s1" != "$s2" ] && echo 1)
out=$(run $M2); ok "0032 tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0032 vooraf" && [ "$(stand)" = "$s2" ] && echo 1) "$out"
ok "bestaande trigger-functies en module-stand ongewijzigd na 0031-0032" $([ "$(rest)" = "$r0" ] && [[ "$r0" != MEETFOUT* ]] && echo 1)
ok "harnas run(10) 0 FAIL na 0031-0032" $([ "$(fails 10)" = "0" ] && echo 1)

# 2. rollbacks: verkeerde volgorde afgebroken, goede volgorde exact terug
out=$(run $R1); ok "0031-rollback met 0032 aanwezig: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0031-rollback vooraf" && [ "$(stand)" = "$s2" ] && echo 1) "$out"
out=$(run $R2); ok "0032-rollback: exact terug naar de stand na 0031" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s1" ] && echo 1) "$out"
out=$(run $R2); ok "0032 tweede rollback: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0032-rollback vooraf" && [ "$(stand)" = "$s1" ] && echo 1) "$out"
out=$(run $R1); ok "0031-rollback: exact terug naar 0030" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s0" ] && echo 1) "$out"
ok "na alle rollbacks: harnas run(9) 0 FAIL (oude stand, ook het oude lek)" $([ "$(fails 9)" = "0" ] && echo 1)
ok "bestaande trigger-functies en module-stand ongewijzigd na rollbacks" $([ "$(rest)" = "$r0" ] && echo 1)
out=$(run $M1)$(run $M2); ok "0031-0032 na rollback opnieuw: slaagt, zelfde stand" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s2" ] && echo 1) "$out"

# 3. verkeerde uitgangsstand: een extra policy op facturen -> 0031 afgebroken
vers; sql "create policy proef on public.invoices for select using (false)" >/dev/null; sa=$(stand)
out=$(run $M1); ok "0031 met onverwachte extra policy: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0031 vooraf" && [ "$(stand)" = "$sa" ] && echo 1) "$out"

# 4. bewust kapotte versies: het harnas moet ze vangen (run(10) > 0 FAIL)
mutant() {  # $1 naam, $2 bestand (1|2), $3 python-vervanging (oud), $4 (nieuw)
  local m=/tmp/fa_mut.sql src; [ "$2" = "1" ] && src=$M1 || src=$M2
  python3 -c "import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[2])>=1, 'tekst niet gevonden'; open(sys.argv[4],'w').write(s.replace(sys.argv[2], sys.argv[3]))" "$src" "$3" "$4" "$m" \
    || { ok "mutatie $1: tekst gevonden" 0; return; }
  vers
  if [ "$2" = "1" ]; then out=$(run $m)$(run $M2); else out=$(run $M1)$(run $m); fi
  local n; n=$(fails 10)
  ok "mutatie $1: gevangen ($n FAIL)" $([ -z "$(echo "$out" | grep -i error)" ] && [ "${n:-0}" -gt 0 ] && echo 1) "$out"
}
mutant "paid -> sent toegestaan" 2 "('overdue','paid'))" "('overdue','paid'), ('paid','sent'))"
mutant "draft -> overdue toegestaan" 2 "('sent','overdue')," "('sent','overdue'), ('draft','overdue'),"
mutant "bedrag na draft wijzigbaar" 2 "if old.status <> 'draft' and to_jsonb" "if false and to_jsonb"
mutant "verzonden factuur wisbaar" 2 "if old.status <> 'draft' then raise" "if false then raise"
mutant "nieuwe factuur niet-draft" 2 "if new.status <> 'draft' then raise" "if false then raise"
mutant "regel verplaatsen toegestaan" 2 " or old.invoice_id <> new.invoice_id" ""
mutant "regel op verzonden factuur" 2 "s is distinct from 'draft' or" "false or"
mutant "betaling op betaalde factuur" 2 "s = 'paid' or " ""
mutant "betaling van 0" 2 "not (new.amount > 0)" "not (new.amount >= 0)"
mutant "kindwacht als invoker (ziet factuur niet)" 2 "invoice_child_guard() returns trigger language plpgsql security definer" "invoice_child_guard() returns trigger language plpgsql"
mutant "service_role-uitzondering in de factuurwacht" 2 "begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth()" "begin
  if coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role', current_setting('role')) = 'service_role' then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    if pg_trigger_depth()"
mutant "bediening leest facturen" 1 "using (%s and public.has_perm(''VIEW_REVENUE''))', r);" "using (%s)', r);"
mutant "manager registreert betaling" 1 "k := k || ' and public.has_perm(''MANAGE_INVOICES'')';" "k := k || ' and public.has_perm(''VIEW_REVENUE'')';"
mutant "manager leest documenten" 1 "\"documents select\" on public.documents for select to authenticated using (%s and public.has_perm(''MANAGE_INVOICES''))" "\"documents select\" on public.documents for select to authenticated using (%s and public.has_perm(''VIEW_REVENUE''))"
# twee lagen: zonder de draft-eis in RLS houdt de wacht een niet-draft factuur nog steeds tegen (en omgekeerd)
twee_lagen() {  # $1 naam, $2 bestand, $3 oud, $4 nieuw, $5 case die moet blijven slagen
  local m=/tmp/fa_mut.sql src; [ "$2" = "1" ] && src=$M1 || src=$M2
  python3 -c "import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[2])>=1; open(sys.argv[4],'w').write(s.replace(sys.argv[2], sys.argv[3]))" "$src" "$3" "$4" "$m" || { ok "$1: tekst gevonden" 0; return; }
  vers; if [ "$2" = "1" ]; then out=$(run $m)$(run $M2); else out=$(run $M1)$(run $m); fi
  ok "$1" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(sql "select result from hardening_test.run(10) where id = '$5'")" = "PASS" ] && echo 1) "$out"
}
twee_lagen "RLS zonder draft-eis: de wacht weigert een directe sent-factuur nog steeds (FW31)" 1 " and status = ''draft''" "" FW31
twee_lagen "wacht zonder draft-eis: RLS weigert een directe sent-factuur nog steeds (FW31)" 2 "if new.status <> 'draft' then raise" "if false then raise" FW31

$PSQL -d postgres -c "drop database if exists fa_test" >/dev/null 2>&1; rm -f /tmp/fa_mut.sql
echo "RESULTAAT: $pass PASS, $fail FAIL"
[ $fail -eq 0 ]
