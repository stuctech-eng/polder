#!/usr/bin/env bash
# Tests voor migraties 0033-0034 (rolrechten dagafsluiting, bedrijfsgegevens, instellingen, ongebruikte tabellen dicht), de rollbacks
# en bewust kapotte versies (ALLEEN lokaal; maakt en verwijdert eigen kopie-databases).
# Gebruik:  PSQL="psql -X -q -h /socketdir -p 55432 -U postgres" BASIS=<database t/m 0032 met seed en harnas> bash stamdata-tests.sh
# BASIS bouw je met:  TOT=0032 DB=<naam> bash local-build.sh
set -uo pipefail
PSQL=${PSQL:-"psql -X -q"}; BASIS=${BASIS:?BASIS = database t/m 0032}
cd "$(dirname "$0")/../.."          # = supabase/
M1=migrations/0033_rolrechten_dagafsluiting_bedrijven.sql; M2=migrations/0034_rolrechten_instellingen.sql
R1=rollbacks/0033_rollback.sql; R2=rollbacks/0034_rollback.sql
T="'daily_closings','companies','departments','cost_centers','projects','company_codes','configurations','workflow_rules','approval_settings','contacts','integration_plugins','email_settings','notifications'"
pass=0; fail=0
ok()   { if [ "${2:-}" = "1" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
vers() { $PSQL -d postgres -c "drop database if exists sd_test" -c "create database sd_test template $BASIS" >/dev/null 2>&1; }
run()  { $PSQL -d sd_test -c "$(cat "$1")" 2>&1; }
sql()  { $PSQL -d sd_test -At -c "$1" 2>/dev/null; }
geldig() { if [[ "$1" =~ ^[0-9a-f]{32}$ ]]; then echo "$1"; else echo "MEETFOUT-$RANDOM-$RANDOM"; fi; }
# vingerafdruk van alles wat 0033-0034 raakt: policies (naam, soort, rollen, tekst) en RLS-vlag op de 13 tabellen
stand() { geldig "$(sql "select md5(
  coalesce((select string_agg(tablename||policyname||cmd||array_to_string(roles,',')||coalesce(qual,'')||coalesce(with_check,''), '|' order by tablename, policyname)
    from pg_policies where schemaname='public' and tablename in ($T)),'')
  || coalesce((select string_agg(relname||relrowsecurity::text, '|' order by relname) from pg_class where relnamespace='public'::regnamespace and relname in ($T)),''))" | tail -1)"; }
# alles wat NIET mag veranderen: alle trigger-functies (incl. module_wacht en factuurwacht), alle triggers, module-stand, policies op andere tabellen
rest() { geldig "$(sql "select md5(coalesce((select string_agg(proname||md5(prosrc)||prosecdef::text, '|' order by proname) from pg_proc
    where pronamespace='public'::regnamespace and prorettype='trigger'::regtype),'')
  || coalesce((select string_agg(pg_get_triggerdef(oid), '|' order by 1) from pg_trigger where not tgisinternal),'')
  || coalesce((select string_agg(r.id||k||public.feature_aan(r.id,k)::text, '|' order by r.id, k) from public.restaurants r
    cross join (values ('daily_closing'),('payment_registration'),('approval')) v(k)),'')
  || coalesce((select string_agg(tablename||policyname||coalesce(qual,'')||coalesce(with_check,''), '|' order by tablename, policyname)
    from pg_policies where schemaname='public' and tablename not in ($T)),''))" | tail -1)"; }
fails() { sql "select count(*) from hardening_test.run($1) where result = 'FAIL'"; }
# email_settings bestaat in productie niet (migratie 0002 nooit uitgevoerd): het harnas slaat precies die 5 cases expliciet over (SKIP)
skips() { sql "select coalesce(string_agg(id, ',' order by id), '') from hardening_test.run($1) where result = 'SKIP'"; }
# het productie-leesblok: stand|tabellen|policies|policies_all|all_in_public|dicht_ok
leesblok() { $PSQL -d sd_test -At -F'|' -f hardening/prod-stamdata-checks.sql 2>&1 | grep -v '^$' | head -1 | cut -d'|' -f1-6; }

echo "== $($PSQL -d postgres -At -c 'show server_version')"
ok "4 blokken passen in de editor (< 3000 tekens)" $(for f in $M1 $M2 $R1 $R2; do [ "$(wc -c < $f)" -lt 3000 ] || exit; done; echo 1)

# 1. heen, met tweede keer = afgebroken zonder wijziging
vers; s0=$(stand); r0=$(rest); NT=$(sql "select count(*) from unnest(array[$T]) x where to_regclass('public.' || x) is not null")
echo "== tabellen: $NT (12 = zoals productie, zonder email_settings)"
ok "leesblok vooraf: 0032|$NT|$NT|$NT|$NT|leeg" $([ "$(leesblok)" = "0032|$NT|$NT|$NT|$NT|" ] && echo 1) "$(leesblok)"
ok "uitgangsstand: harnas run(10) 0 FAIL" $([ "$(fails 10)" = "0" ] && echo 1)
out=$(run $M2); ok "0034 zonder 0033: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0034 vooraf" && [ "$(stand)" = "$s0" ] && echo 1) "$out"
out=$(run $R1); ok "0033-rollback zonder 0033: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0033-rollback vooraf" && [ "$(stand)" = "$s0" ] && echo 1) "$out"
out=$(run $R2); ok "0034-rollback zonder 0034: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0034-rollback vooraf" && [ "$(stand)" = "$s0" ] && echo 1) "$out"
out=$(run $M1); ok "0033 slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"; s1=$(stand)
ok "0033: meting ziet de wijziging" $([ "$s0" != "$s1" ] && [[ "$s0" != MEETFOUT* ]] && echo 1)
ok "leesblok na 0033: 0033|$NT|$((NT+7))|$((NT-6))|$((NT-6))|leeg" $([ "$(leesblok)" = "0033|$NT|$((NT+7))|$((NT-6))|$((NT-6))|" ] && echo 1) "$(leesblok)"
out=$(run $M1); ok "0033 tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0033 vooraf" && [ "$(stand)" = "$s1" ] && echo 1) "$out"
out=$(run $M2); ok "0034 slaagt" $([ -z "$(echo "$out" | grep -i error)" ] && echo 1) "$out"; s2=$(stand)
ok "0034: meting ziet de wijziging" $([ "$s1" != "$s2" ] && echo 1)
ok "leesblok na 0034: 0034|$NT|22|0|0|t" $([ "$(leesblok)" = "0034|$NT|22|0|0|t" ] && echo 1) "$(leesblok)"
out=$(run $M2); ok "0034 tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0034 vooraf" && [ "$(stand)" = "$s2" ] && echo 1) "$out"
ok "geen enkele ALL-policy meer in public" $([ "$(sql "select count(*) from pg_policies where schemaname='public' and cmd='ALL'")" = "0" ] && echo 1)
ok "triggers, guards, module_wacht, module-stand en overige policies ongewijzigd na 0033-0034" $([ "$(rest)" = "$r0" ] && [[ "$r0" != MEETFOUT* ]] && echo 1)
ok "harnas run(11) 0 FAIL na 0033-0034" $([ "$(fails 11)" = "0" ] && echo 1)
VERWACHT_SKIP=$([ "$NT" = "12" ] && echo "RR62c,RR62d,RR62i,RR62s,RR62u" || echo "")
ok "overgeslagen cases precies: '${VERWACHT_SKIP:-geen}'" $([ "$(skips 11)" = "$VERWACHT_SKIP" ] && echo 1) "$(skips 11)"

# 2. rollbacks: verkeerde volgorde afgebroken, goede volgorde exact terug
out=$(run $R1); ok "0033-rollback met 0034 aanwezig: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0033-rollback vooraf" && [ "$(stand)" = "$s2" ] && echo 1) "$out"
out=$(run $R2); ok "0034-rollback: exact terug naar de stand na 0033" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s1" ] && echo 1) "$out"
out=$(run $R2); ok "0034 tweede rollback: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0034-rollback vooraf" && [ "$(stand)" = "$s1" ] && echo 1) "$out"
out=$(run $R1); ok "0033-rollback: exact terug naar 0032 (ook email_settings met de oude tekst)" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s0" ] && echo 1) "$out"
ok "na alle rollbacks: harnas run(10) 0 FAIL (oude stand, ook het oude lek)" $([ "$(fails 10)" = "0" ] && echo 1)
ok "triggers, guards, module-stand en overige policies ongewijzigd na rollbacks" $([ "$(rest)" = "$r0" ] && echo 1)
out=$(run $M1)$(run $M2); ok "0033-0034 na rollback opnieuw: slaagt, zelfde stand" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(stand)" = "$s2" ] && echo 1) "$out"

# 3. verkeerde uitgangsstand: een extra policy -> afgebroken
vers; sql "create policy proef on public.companies for select using (false)" >/dev/null; sa=$(stand)
out=$(run $M1); ok "0033 met onverwachte extra policy op companies: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0033 vooraf" && [ "$(stand)" = "$sa" ] && echo 1) "$out"
vers; run $M1 >/dev/null; sql "create policy proef on public.contacts for select using (true)" >/dev/null; sb=$(stand)
out=$(run $M2); ok "0034 met onverwachte extra policy op contacts: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0034 vooraf" && [ "$(stand)" = "$sb" ] && echo 1) "$out"

# 3b. rollback 0034 op een afwijkende stand (zelfde aantal policies, andere verdeling): afgebroken, niets gewijzigd
vers; run $M1 >/dev/null; run $M2 >/dev/null
sql "drop policy \"workflow_rules update\" on public.workflow_rules" >/dev/null
sql "create policy \"workflow_rules delete\" on public.workflow_rules for delete to authenticated using (true)" >/dev/null; sc=$(stand)
out=$(run $R2); ok "0034-rollback: 9 policies maar een wis- in plaats van wijzig-policy: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0034-rollback vooraf" && [ "$(stand)" = "$sc" ] && echo 1) "$out"
vers; run $M1 >/dev/null; run $M2 >/dev/null
sql "alter policy \"configurations select\" on public.configurations rename to \"configurations lezen\"" >/dev/null; sc=$(stand)
out=$(run $R2); ok "0034-rollback: policy met afwijkende naam: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0034-rollback vooraf" && [ "$(stand)" = "$sc" ] && echo 1) "$out"
vers; run $M1 >/dev/null; run $M2 >/dev/null
sql "create policy proef on public.notifications for select to authenticated using (false)" >/dev/null; sc=$(stand)
out=$(run $R2); ok "0034-rollback: extra policy op een dichte tabel: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0034-rollback vooraf" && [ "$(stand)" = "$sc" ] && echo 1) "$out"
vers; run $M1 >/dev/null; run $M2 >/dev/null
sql "alter policy \"approval_settings update\" on public.approval_settings to public" >/dev/null; sc=$(stand)
out=$(run $R2); ok "0034-rollback: policy voor een andere rol: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "0034-rollback vooraf" && [ "$(stand)" = "$sc" ] && echo 1) "$out"

# 4. bewust kapotte versies: het harnas moet ze vangen (run(11) > 0 FAIL)
mutant() {  # $1 naam, $2 bestand (1|2), $3 oud, $4 nieuw
  local m=/tmp/sd_mut.sql src; [ "$2" = "1" ] && src=$M1 || src=$M2
  python3 -c "import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[2])>=1, 'tekst niet gevonden'; open(sys.argv[4],'w').write(s.replace(sys.argv[2], sys.argv[3]))" "$src" "$3" "$4" "$m" \
    || { ok "mutatie $1: tekst gevonden" 0; return; }
  vers
  if [ "$2" = "1" ]; then out=$(run $m)$(run $M2); else out=$(run $M1)$(run $m); fi
  local n; n=$(fails 11)
  ok "mutatie $1: gevangen ($n FAIL)" $([ -z "$(echo "$out" | grep -i error)" ] && [ "${n:-0}" -gt 0 ] && echo 1) "$out"
}
mutant "dagafsluiting niet op eigen naam" 1 " and closed_by = auth.uid()" ""
mutant "dagafsluiting met VIEW in plaats van EXECUTE" 1 "has_perm(''EXECUTE_DAILY_CLOSING'')" "has_perm(''VIEW_DAILY_CLOSING'')"
mutant "dagafsluiting leesbaar voor iedereen" 1 "using (%s and public.has_perm(''VIEW_DAILY_CLOSING''))" "using (%s)"
mutant "bedrijf wijzigen zonder MANAGE_COMPANIES" 1 "using (%1\$s and public.has_perm(''MANAGE_COMPANIES'')) with check (%1\$s and public.has_perm(''MANAGE_COMPANIES''))" "using (%1\$s) with check (%1\$s)"
mutant "afdeling aanmaken zonder MANAGE_COMPANIES" 1 "with check (%s and public.has_perm(''MANAGE_COMPANIES''))', t || ' insert'" "with check (%s)', t || ' insert'"
mutant "bedrijven alleen voor MANAGE_COMPANIES leesbaar (bediening kan geen rekening openen)" 1 "\"companies select\" on public.companies for select to authenticated using (%s)', r)" "\"companies select\" on public.companies for select to authenticated using (%s and public.has_perm(''MANAGE_COMPANIES''))', r)"
mutant "instellingen wijzigen zonder MANAGE_SETTINGS" 2 "k := k || ' and public.has_perm(''MANAGE_SETTINGS'')';" "k := k;"
# toevoegingen ná de echte migraties (een extra policy zou de nacontrole van de migratie zelf al laten falen)
extra() {  # $1 naam, $2 sql
  vers; local out; out=$(run $M1)$(run $M2)$($PSQL -d sd_test -c "$2" 2>&1)
  local n; n=$(fails 11)
  ok "mutatie $1: gevangen ($n FAIL)" $([ -z "$(echo "$out" | grep -i error)" ] && [ "${n:-0}" -gt 0 ] && echo 1) "$out"
}
extra "wis-policy op instellingen (owner mag wissen)" "create policy proef on public.workflow_rules for delete to authenticated using (restaurant_id = public.my_restaurant_id())"
extra "wis-policy op dagafsluiting" "create policy proef on public.daily_closings for delete to authenticated using (restaurant_id = public.my_restaurant_id())"
extra "ongebruikte tabel contacts weer leesbaar" "create policy proef on public.contacts for select to authenticated using (true)"
[ "$NT" = "13" ] && extra "ongebruikte tabel email_settings weer schrijfbaar" "create policy proef on public.email_settings for insert to authenticated with check (true)"
extra "wijzig-policy op afdelingen" "create policy proef on public.departments for update to authenticated using (true)"
$PSQL -d postgres -c "drop database if exists sd_test" >/dev/null 2>&1; rm -f /tmp/sd_mut.sql
echo "RESULTAAT: $pass PASS, $fail FAIL"
[ $fail -eq 0 ]
