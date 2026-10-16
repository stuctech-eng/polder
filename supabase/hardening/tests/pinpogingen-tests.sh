#!/usr/bin/env bash
# Tests voor stap 14a (migraties 0037-0042: PIN-pogingen, PIN-eis en bon indienen in de database), de rollbacks, het controleblok, vaste volgordes,
# gelijktijdigheid en bewust kapotte versies (ALLEEN lokaal; maakt en verwijdert eigen kopie-databases).
# Gebruik:  PSQL="psql -X -q -h /socketdir -p <poort> -U postgres" BASIS=<database> bash pinpogingen-tests.sh [snel]
#   BASIS = t/m 0036 (PostgreSQL 17: TOT=0035 PRODSTAND=1 + 0036) of t/m 0035 (PostgreSQL 16), met seed en harnas.
#   "snel": parallelle test met 10 in plaats van 50 rondes.
set -uo pipefail
PSQL=${PSQL:-"psql -X -q"}; BASIS=${BASIS:?BASIS = database t/m 0036 of 0035}; RONDES=$([ "${1:-}" = snel ] && echo 10 || echo 50)
cd "$(dirname "$0")/../.."          # = supabase/
MIG=(migrations/0037_pin_tabellen.sql migrations/0038_pin_functies.sql migrations/0039_pin_reserveren.sql
     migrations/0040_pin_wachten_instelling_regel.sql migrations/0041_bon_indienen.sql migrations/0042_pin_wacht_bon.sql)
RB=(rollbacks/0037_rollback.sql rollbacks/0038_rollback.sql rollbacks/0039_rollback.sql rollbacks/0040_rollback.sql rollbacks/0041_rollback.sql rollbacks/0042_rollback.sql)
C=hardening/prod-pin14-checks.sql
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
A100=a0000000-0000-0000-0000-000000000100; A105=a0000000-0000-0000-0000-000000000105
BON=a0000000-0000-0000-0000-000000000301; BON0=a0000000-0000-0000-0000-000000000300
OWN=a0000000-0000-0000-0000-000000000010; MGR=a0000000-0000-0000-0000-000000000011
DB=pp_test
pass=0; fail=0
ok()   { if [ "${2:-}" = "1" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
vers() { $PSQL -d postgres -c "drop database if exists $DB" -c "create database $DB template ${1:-$BASIS}" >/dev/null 2>&1; }
run()  { $PSQL -d $DB -c "$(cat "$1")" 2>&1; }
sql()  { $PSQL -d $DB -At -c "$1" 2>/dev/null | tail -1; }
sqlv() { $PSQL -d $DB -At -c "$1" 2>&1; }
# als service_role (de goedkeurroute met de service-sleutel); geeft het resultaat of de foutmelding
svc()  { local o; o=$($PSQL -d $DB -At -c "begin; select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true) is null; set local role service_role; $1; commit;" 2>&1 | grep -v '^$' | grep -v '^f$')
         if echo "$o" | grep -q ERROR; then echo "$o" | grep ERROR | head -1; else echo "$o" | tail -1; fi; }
# als ingelogde gebruiker $1 (uuid); geeft "ok <rijen>" of de foutmelding
als()  { local o; o=$($PSQL -d $DB -At -c "begin; select set_config('request.jwt.claim.sub','$1',true) is null and set_config('request.jwt.claims','{\"role\":\"authenticated\",\"sub\":\"$1\"}',true) is null; set local role authenticated; $2; commit;" 2>&1)
         if echo "$o" | grep -qi error; then echo "$o" | grep -i error | head -1; else echo "ok $(echo "$o" | grep -c '^[0-9a-f]\{8\}-')"; fi; }
start()   { svc "select r->>'toegestaan', coalesce(r->>'id',''), coalesce(r->>'reden',''), coalesce(r->>'blokkade_gezet','') from (select public.pin_poging_start('${1:-$A100}','${2:-$BON}') r) x" | tr '|' ' '; }
startid() { start "$@" | awk '$1=="true"{print $2}'; }
afrond()  { svc "select public.pin_poging_afronden('$1', $2)"; }
goedkeur(){ als ${2:-$MGR} "update receipts set status='${3:-approved}' where id='${1:-$BON}' and status='pending_approval' returning id"; }
pinwissel(){ als $OWN "update approval_settings set pin_hash = md5(random()::text), pin_salt = 'x' where company_id='${1:-$A100}' returning id"; }
telling() { sql "select count(*) from pin_reserveringen r join pin_pogingen p using (company_id) where r.company_id='${1:-$A100}' and r.generatie=p.generatie and r.status in ('lopend','fout') and r.gemaakt_op > clock_timestamp() - interval '15 minutes'"; }
blok()    { sql "select coalesce(geblokkeerd_tot::text,'') from pin_pogingen where company_id='${1:-$A100}'"; }
bonst()   { sql "select status from receipts where id='${1:-$BON}'"; }
check()   { $PSQL -d $DB -At -F'|' -f $C 2>&1 | grep -v '^$' | head -1; }
fails()   { sql "select count(*) from hardening_test.run($1) where result = 'FAIL'"; }
faillijst(){ sql "select coalesce(string_agg(id, ',' order by id), '') from hardening_test.run($1) where result = 'FAIL'"; }
alle_mig(){ for f in "${MIG[@]}"; do run $f >/dev/null; done; }
# bewust kapotte versie van een functie: $1 functie (regprocedure), $2 oud, $3 nieuw (python-vervanging, moet precies 1x voorkomen)
muteer() { local d; d=$(sql "select pg_get_functiondef('$1'::regprocedure)" ); $PSQL -d $DB -At -c "select pg_get_functiondef('$1'::regprocedure)" > $TMP/f.sql
  python3 - $TMP/f.sql "$2" "$3" <<'E'
import sys; p, o, n = sys.argv[1:4]; s = open(p).read(); assert s.count(o) == 1, "mutatie niet uniek: " + o; open(p, 'w').write(s.replace(o, n))
E
  $PSQL -d $DB -c "$(cat $TMP/f.sql)" >/dev/null 2>&1 || echo "MUTATIE FAALDE"; }

V=$($PSQL -d postgres -At -c 'show server_version_num'); echo "== PostgreSQL $($PSQL -d postgres -At -c 'show server_version')"
ok "13 blokken passen in de editor (< 3000 tekens)" $(for f in "${MIG[@]}" "${RB[@]}" $C; do [ "$(wc -c < $f)" -lt 3000 ] || exit; done; echo 1)

# 1. uitgangsstand en volgorde
vers; c0=$(check); m0=$(echo "$c0" | cut -d'|' -f5)
ok "uitgangsstand: controleblok 0036|000000|t|0" $([ "$(echo "$c0" | cut -d'|' -f1-4)" = "0036|000000|t|0" ] && echo 1) "$c0"
# 0036 (stap 13) staat alleen op de PG17-productiestand; zonder 0036 zijn de stap-13-cases bij run(14) de bekende uitzondering
if [ "$(sql "select has_table_privilege('authenticated','public.contacts','select')")" = "f" ]; then B=13; X13=""; else B=12
  X13=$(faillijst 13); fi   # de stap-13-cases die hier echt gelden (OR05/OR06 worden op PG16 overgeslagen)
echo "== basis: stap $B (0036 $([ $B = 13 ] && echo aanwezig || echo 'niet aanwezig'))"
lijst() { python3 -c "import sys; print(','.join(sorted(x for x in ','.join(sys.argv[1:]).split(',') if x)))" "$@"; }
ok "uitgangsstand: harnas run($B) 0 FAIL" $([ "$(fails $B)" = "0" ] && echo 1) "$(faillijst $B)"
S14=$(sql "select string_agg(id, ',' order by id) from hardening_test.cases where step = 14 and expect_after is distinct from expect_now")
ok "uitgangsstand: run(14) faalt precies op de stap-14-cases ($S14)" $([ -n "$S14" ] && [ "$(faillijst 14)" = "$(lijst "$S14" "$X13")" ] && echo 1) "$(faillijst 14)"
for i in 1 2 3 4 5; do out=$(run ${MIG[$i]}); ok "$(basename ${MIG[$i]}) zonder voorganger: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "vooraf" && [ "$(check)" = "$c0" ] && echo 1) "$out"; done
for i in 0 1 2 3 4 5; do out=$(run ${RB[$i]}); ok "$(basename ${RB[$i]}) zonder migratie: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "rollback vooraf" && [ "$(check)" = "$c0" ] && echo 1) "$out"; done

# 2. heen, stap voor stap
STANDEN=(0037 0038 0039 0040 0041 0042); BITS=(100000 110000 111000 111100 111110 111111)
for i in 0 1 2 3 4 5; do
  out=$(run ${MIG[$i]}); c=$(check)
  ok "$(basename ${MIG[$i]}) slaagt; controleblok ${STANDEN[$i]}|${BITS[$i]}|t, bestaand_md5 gelijk" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(echo "$c" | cut -d'|' -f1-3)" = "${STANDEN[$i]}|${BITS[$i]}|t" ] && [ "$(echo "$c" | cut -d'|' -f5)" = "$m0" ] && echo 1) "$out $c"
  out=$(run ${MIG[$i]}); ok "$(basename ${MIG[$i]}) tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "vooraf" && [ "$(check)" = "$c" ] && echo 1) "$out"
done
ok "harnas run(14) na 0037-0042: 0 FAIL$([ -n "$X13" ] && echo ' (behalve de stap-13-cases: 0036 ontbreekt)')" $([ "$(faillijst 14)" = "$(lijst "$X13")" ] && echo 1) "$(faillijst 14)"
ok "triggervolgorde receipts: module_wacht, receipts_guard, receipts_pin_wacht, xref_*" $([ "$(sql "select string_agg(tgname, ',' order by tgname) from pg_trigger where tgrelid = 'public.receipts'::regclass and not tgisinternal")" = "module_wacht,receipts_guard,receipts_pin_wacht,xref_keys_immutable,xref_receipts,xref_user_ref" ] && echo 1)
ok "triggervolgorde approvals: approvals_guard, approvals_pin_wacht, module_wacht, xref_approvals" $([ "$(sql "select string_agg(tgname, ',' order by tgname) from pg_trigger where tgrelid = 'public.approvals'::regclass and not tgisinternal")" = "approvals_guard,approvals_pin_wacht,module_wacht,xref_approvals" ] && echo 1)
cp_na() { $PSQL -d postgres -c "drop database if exists pp_na" -c "create database pp_na template $DB" >/dev/null 2>&1; }
# basis voor alle volgordetests: alles t/m 0042, en bon 301 is een PIN-bon (wachtende PIN-regel; in de seed is het een qr-regel)
cp_na; $PSQL -d pp_na -c "set session_replication_role = replica; update approvals set method = 'pin' where receipt_id = '$BON'" >/dev/null
ok "bon 301 met wachtende PIN-regel: pin_eis = bedrijf A" $([ "$($PSQL -d pp_na -At -c "select public.pin_eis('$BON')")" = "$A100" ] && echo 1)
# 3. terug, stap voor stap, exact
for i in 5 4 3 2 1 0; do out=$(run ${RB[$i]}); ok "$(basename ${RB[$i]}) slaagt, bestaand_md5 gelijk" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(check | cut -d'|' -f5)" = "$m0" ] && echo 1) "$out"; done
ok "na alle rollbacks: controleblok exact als vooraf" $([ "$(check)" = "$c0" ] && echo 1) "$(check)"
ok "na alle rollbacks: harnas run($B) 0 FAIL" $([ "$(fails $B)" = "0" ] && echo 1) "$(faillijst $B)"
alle_mig; ok "opnieuw heen na rollback: slaagt (0042)" $([ "$(check | cut -d'|' -f1)" = "0042" ] && echo 1)

# 4. vaste volgordes (elk op een verse kopie t/m 0042)
na() { vers pp_na; }
# a. 5x start, 5e zet blokkade; juist laat blokkade staan
na; ids=(); for k in 1 2 3 4 5; do ids+=($(startid)); done; b=$(blok)
ok "a: 5 reserveringen toegelaten, de 5e zet de blokkade" $([ "${#ids[@]}" = "5" ] && [ -n "$b" ] && echo 1) "${#ids[@]} $b"
ok "a: 6e geweigerd (geblokkeerd)" $(start | grep -q "false  geblokkeerd" && echo 1) "$(start)"
r=$(afrond ${ids[0]} true); ok "a: juist op een van de vijf: ok, blokkade exact gelijk, telling 4" $([ "$r" = "ok" ] && [ "$(blok)" = "$b" ] && [ "$(telling)" = "4" ] && echo 1) "$r $(blok) $(telling)"
ok "a: daarna nog steeds geweigerd" $(start | grep -q "geblokkeerd" && echo 1)
# b. 3 start, 1 juist -> precies 3 nieuwe
na; i1=$(startid); i2=$(startid); i3=$(startid); afrond $i1 true >/dev/null; n=0; for k in 1 2 3 4; do [ -n "$(startid)" ] && n=$((n+1)); done
ok "b: 3 reserveringen, 1 juist -> precies 3 nieuwe toegelaten, de 4e geweigerd" $([ "$n" = "3" ] && [ "$(telling)" = "5" ] && echo 1) "$n $(telling)"
# c. dubbel afronden
na; i=$(startid); r1=$(afrond $i true); r2=$(afrond $i true); r3=$(afrond $i false)
ok "c: eerste afronden ok, tweede en derde al_afgerond, status juist" $([ "$r1 $r2 $r3" = "ok al_afgerond al_afgerond" ] && [ "$(sql "select status from pin_reserveringen where id='$i'")" = "juist" ] && echo 1) "$r1 $r2 $r3"
i=$(startid); afrond $i false >/dev/null; ok "c: eerst fout dan juist -> al_afgerond, blijft fout" $([ "$(afrond $i true)" = "al_afgerond" ] && [ "$(sql "select status from pin_reserveringen where id='$i'")" = "fout" ] && echo 1)
ok "c: onbekend id -> onbekend, niets gewijzigd" $([ "$(afrond 00000000-0000-0000-0000-000000000099 true)" = "onbekend" ] && echo 1)
# d. start -> PIN wijzigen -> afronden = verlopen (definitief)
na; i=$(startid); pinwissel >/dev/null; r1=$(afrond $i true); r2=$(afrond $i true)
ok "d: na PIN-wijziging: verlopen, daarna al_afgerond, status verlopen" $([ "$r1 $r2" = "verlopen al_afgerond" ] && [ "$(sql "select status from pin_reserveringen where id='$i'")" = "verlopen" ] && echo 1) "$r1 $r2"
n=0; for k in 1 2 3 4 5 6; do [ -n "$(startid)" ] && n=$((n+1)); done; ok "d: nieuwe generatie telt opnieuw: 5 toegelaten" $([ "$n" = "5" ] && echo 1) "$n"
# e. crash
na; startid >/dev/null; ok "e: reservering zonder afronden telt mee (lopend)" $([ "$(telling)" = "1" ] && echo 1)
# f. grens 15 min en blokkade
na; i=$(startid); j=$(startid); sql "update pin_reserveringen set gemaakt_op = clock_timestamp() - interval '15 minutes' + interval '1 second' where id='$i'; update pin_reserveringen set gemaakt_op = clock_timestamp() - interval '15 minutes' - interval '1 second' where id='$j'" >/dev/null
ok "f: 15 min - 1 s telt, 15 min + 1 s niet" $([ "$(telling)" = "1" ] && echo 1) "$(telling)"
sql "update pin_pogingen set geblokkeerd_tot = clock_timestamp() + interval '1 second' where company_id='$A100'" >/dev/null; ok "f: blokkade nog 1 s actief: geweigerd" $(start | grep -q geblokkeerd && echo 1)
sql "update pin_pogingen set geblokkeerd_tot = clock_timestamp() - interval '1 second' where company_id='$A100'" >/dev/null; ok "f: blokkade 1 s verlopen: toegelaten" $([ -n "$(startid)" ] && echo 1)
# g. tijd onder het slot: A begint eerder (transactie), wacht op B's slot, krijgt een latere tijd
na; ( $PSQL -d $DB -c "begin; set local role service_role; select pg_sleep(0.6); select public.pin_poging_start('$A100','$BON'); commit;" >/dev/null 2>&1 ) &
sleep 0.2; ( $PSQL -d $DB -c "begin; set local role service_role; select public.pin_poging_start('$A100','$BON'); select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) & wait
ok "g: wie op het slot wachtte, krijgt een latere tijd (clock_timestamp onder het slot)" $([ "$(sql "select count(*) from pin_reserveringen")" = "2" ] && [ "$(sql "select (max(gemaakt_op) - min(gemaakt_op)) > interval '1 second' from pin_reserveringen")" = "t" ] && echo 1) "$(sqlv "select gemaakt_op from pin_reserveringen order by 1")"
# h. punt 2 volgorde A: goedkeuren en committen, dan PIN wijzigen
na; i=$(startid); afrond $i true >/dev/null; g=$(goedkeur); pinwissel >/dev/null
ok "h: goedkeuring vóór PIN-wijziging blijft staan, reservering verbruikt" $([ "$g" = "ok 1" ] && [ "$(bonst)" = "approved" ] && [ "$(sql "select verbruikt_op is not null from pin_reserveringen where id='$i'")" = "t" ] && echo 1) "$g"
# i. volgorde B: juist, PIN wijzigen, dan goedkeuren
na; i=$(startid); afrond $i true >/dev/null; pinwissel >/dev/null; g=$(goedkeur)
ok "i: PIN gewijzigd na juist -> goedkeuring geweigerd, bon wacht nog" $(echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && [ "$(bonst)" = "pending_approval" ] && echo 1) "$g"
# j. gelijktijdig: bon-update houdt het slot vast, PIN-wijziging wacht; en omgekeerd
na; i=$(startid); afrond $i true >/dev/null
( $PSQL -d $DB -c "begin; select set_config('request.jwt.claim.sub','$MGR',true); set local role authenticated; update receipts set status='approved' where id='$BON'; select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
sleep 0.4; s0=$(date +%s.%N); pinwissel >/dev/null; s1=$(date +%s.%N); wait
ok "j1: PIN-wijziging wachtte op de goedkeuring, bon goedgekeurd" $([ "$(bonst)" = "approved" ] && [ "$(echo "$s1 - $s0 > 0.8" | bc)" = "1" ] && echo 1) "$(bonst) $(echo "$s1 - $s0" | bc)"
na; i=$(startid); afrond $i true >/dev/null
( $PSQL -d $DB -c "begin; select set_config('request.jwt.claim.sub','$OWN',true); set local role authenticated; update approval_settings set pin_hash = 'nieuw' where company_id='$A100'; select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
sleep 0.4; g=$(goedkeur); wait
ok "j2: goedkeuring wachtte op de PIN-wijziging en werd daarna geweigerd" $(echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && [ "$(bonst)" = "pending_approval" ] && echo 1) "$g"
# k. hergebruik, andere bon, verlopen geldigheid
na; i=$(startid); afrond $i true >/dev/null; g1=$(goedkeur); g2=$(goedkeur $BON0)
ok "k: één juist -> één goedkeuring; andere bon (linked) niet geraakt" $([ "$g1" = "ok 1" ] && [ "$(sql "select count(*) from pin_reserveringen where verbruikt_op is not null")" = "1" ] && echo 1) "$g1 $g2"
na; sql "update receipts set status='pending_approval' where id='$BON0'" >/dev/null 2>&1
sql "set session_replication_role = replica; update receipts set status='pending_approval' where id='$BON0'" >/dev/null
i=$(startid); afrond $i true >/dev/null; g=$(goedkeur $BON0)
ok "k: juist voor bon 301 -> bon 300 goedkeuren geweigerd" $(echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && echo 1) "$g"
na; i=$(startid); afrond $i true >/dev/null; sql "update pin_reserveringen set afgerond_op = clock_timestamp() - interval '121 seconds' where id='$i'" >/dev/null; g=$(goedkeur)
ok "k: juist ouder dan 2 minuten -> geweigerd" $(echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && echo 1) "$g"
na; sql "insert into pin_pogingen (company_id) values ('$A105') on conflict do nothing; insert into pin_reserveringen (company_id, receipt_id, generatie, gemaakt_op, status, afgerond_op) values ('$A105','$BON',1,clock_timestamp(),'juist',clock_timestamp())" >/dev/null
g=$(goedkeur); ok "k: juiste reservering van een ANDER bedrijf voor deze bon -> geweigerd" $(echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && echo 1) "$g"
for st in lopend fout verlopen; do na; i=$(startid); [ $st != lopend ] && sql "update pin_reserveringen set status='$st', afgerond_op=clock_timestamp() where id='$i'" >/dev/null
  g=$(goedkeur); ok "k: reservering met status $st -> geweigerd" $(echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && echo 1) "$g"; done
na; g=$(goedkeur $BON $OWN locked); ok "k: owner rechtstreeks locked zonder reservering -> geweigerd" $(echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && echo 1) "$g"
# l. punt 1: PIN-wijziging faalt / slaagt
na; i=$(startid); g0=$(sql "select generatie from pin_pogingen where company_id='$A100'"); h0=$(sql "select pin_hash from approval_settings where company_id='$A100'")
out=$(als $OWN "update approval_settings set pin_hash = 'nieuw', method = 'bestaat_niet' where company_id='$A100' returning id")
ok "l: PIN-wijziging die faalt -> oude PIN en oude generatie ongewijzigd, reservering nog geldig" $(echo "$out" | grep -qi error && [ "$(sql "select generatie from pin_pogingen where company_id='$A100'")" = "$g0" ] && [ "$(sql "select pin_hash from approval_settings where company_id='$A100'")" = "$h0" ] && [ "$(afrond $i true)" = "ok" ] && echo 1) "$out"
na; i=$(startid); for k in 1 2 3 4; do startid >/dev/null; done; pinwissel >/dev/null
ok "l: PIN-wijziging slaagt -> generatie + 1, blokkade weg, oude reservering verlopen" $([ -z "$(blok)" ] && [ "$(afrond $i true)" = "verlopen" ] && [ -n "$(startid)" ] && echo 1)
# m. punt 3: opgeruimd of onbekend
na; i=$(startid); sql "update pin_reserveringen set gemaakt_op = clock_timestamp() - interval '2 days' where id='$i'" >/dev/null; startid >/dev/null
ok "m: start ruimt reserveringen ouder dan 1 dag op" $([ "$(sql "select count(*) from pin_reserveringen where id='$i'")" = "0" ] && echo 1)
t0=$(telling); b0=$(blok); r=$(afrond $i true); g=$(goedkeur)
ok "m: afronden opgeruimd id -> onbekend, telling en blokkade gelijk, bon niet goedgekeurd" $([ "$r" = "onbekend" ] && [ "$(telling)" = "$t0" ] && [ "$(blok)" = "$b0" ] && echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && echo 1) "$r $g"
# n-o. mislukte bon-update (module uit) en retry
na; i=$(startid); afrond $i true >/dev/null; t0=$(telling)
sql "insert into restaurant_features select restaurant_id, 'approval', false, now() from companies where id='$A100'" >/dev/null
g=$(goedkeur); ok "n: bon-update geweigerd door de modulewacht -> bon wacht, reservering juist en onverbruikt, telling gelijk" $(echo "$g" | grep -qi "module" && [ "$(bonst)" = "pending_approval" ] && [ "$(sql "select status||(verbruikt_op is null) from pin_reserveringen where id='$i'")" = "juisttrue" ] && [ "$(telling)" = "$t0" ] && echo 1) "$g"
sql "delete from restaurant_features where feature='approval'" >/dev/null; g=$(goedkeur)
ok "n: module weer aan, binnen 2 min dezelfde bon -> goedgekeurd en verbruikt" $([ "$g" = "ok 1" ] && [ "$(sql "select verbruikt_op is not null from pin_reserveringen where id='$i'")" = "t" ] && echo 1) "$g"
ok "p/q: nog eens goedkeuren -> 0 rijen (bon is al goedgekeurd), geen tweede verbruik" $([ "$(goedkeur)" = "ok 0" ] && [ "$(sql "select count(*) from pin_reserveringen where verbruikt_op is not null")" = "1" ] && echo 1)
# q. dubbele aanvraag: twee juiste reserveringen, gelijktijdig goedkeuren -> precies één
na; i=$(startid); j=$(startid); afrond $i true >/dev/null; afrond $j true >/dev/null
( goedkeur > $TMP/q1 ) & ( goedkeur > $TMP/q2 ) & wait
ok "q: gelijktijdig twee keer goedkeuren -> precies één bijgewerkt, één verbruik" $([ "$(cat $TMP/q1 $TMP/q2 | sort | tr '\n' ' ')" = "ok 0 ok 1 " ] && [ "$(sql "select count(*) from pin_reserveringen where verbruikt_op is not null")" = "1" ] && echo 1) "$(cat $TMP/q1 $TMP/q2 | tr '\n' ' ')"
# r. bedrijfswissel na indienen als PIN-bon
na; sql "set session_replication_role = replica; insert into approvals (receipt_id, company_id, method, status) values ('$BON','$A100','pin','pending')" >/dev/null
TAB=$(sql "select open_tab_id from receipts where id='$BON'"); sql "set session_replication_role = replica; update open_tabs set company_id='$A105' where id='$TAB'" >/dev/null
ok "r: PIN-bon naar bedrijf zonder PIN gewisseld: eis blijft bij bedrijf A" $([ "$(sql "select public.pin_eis('$BON')")" = "$A100" ] && echo 1)
g=$(goedkeur); ok "r: rechtstreeks goedkeuren na de wissel -> geweigerd" $(echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && echo 1) "$g"
ok "r: reserveren voor het nieuwe bedrijf -> ongeldig" $(start $A105 $BON | grep -q "ongeldig" && echo 1)
i=$(startid); afrond $i true >/dev/null; ok "r: reservering voor bedrijf A -> goedgekeurd" $([ "$(goedkeur)" = "ok 1" ] && echo 1)
# r2. gelijktijdige bedrijfswissel, beide volgordes, met echte tabellen (bon zonder regel: dan telt het huidige bedrijf)
na; sql "set session_replication_role = replica; delete from approvals where receipt_id='$BON'" >/dev/null; TAB=$(sql "select open_tab_id from receipts where id='$BON'")
( $PSQL -d $DB -c "begin; set local session_replication_role = replica; update open_tabs set company_id='$A105' where id='$TAB'; select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
sleep 0.4; g=$(goedkeur); wait
ok "r2: wissel naar bedrijf zonder PIN eerst (geen PIN-regel) -> goedkeuring wachtte en ziet het nieuwe bedrijf: geen PIN-eis" $([ "$g" = "ok 1" ] && echo 1) "$g"
na; sql "set session_replication_role = replica; delete from approvals where receipt_id='$BON'" >/dev/null; TAB=$(sql "select open_tab_id from receipts where id='$BON'"); sql "set session_replication_role = replica; update open_tabs set company_id='$A105' where id='$TAB'" >/dev/null
( $PSQL -d $DB -c "begin; set local session_replication_role = replica; update open_tabs set company_id='$A100' where id='$TAB'; select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
sleep 0.4; g=$(goedkeur); wait
ok "r2: wissel naar PIN-bedrijf eerst -> goedkeuring wachtte en ziet het PIN-bedrijf: geweigerd" $(echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && [ "$(bonst)" = "pending_approval" ] && echo 1) "$g"
na; TAB=$(sql "select open_tab_id from receipts where id='$BON'"); i=$(startid); afrond $i true >/dev/null
( $PSQL -d $DB -c "begin; select set_config('request.jwt.claim.sub','$MGR',true); set local role authenticated; update receipts set status='approved' where id='$BON'; select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
sleep 0.4; s0=$(date +%s.%N); sql "set session_replication_role = replica; update open_tabs set company_id='$A105' where id='$TAB'" >/dev/null; s1=$(date +%s.%N); wait
ok "r2: goedkeuring eerst -> wissel wachtte tot de goedkeuring klaar was" $([ "$(bonst)" = "approved" ] && [ "$(echo "$s1 - $s0 > 0.8" | bc)" = "1" ] && echo 1) "$(bonst) $(echo "$s1 - $s0" | bc)"
# r3. dezelfde PIN-eis in reserveren en wacht
# r3. methode per bon: een wachtende qr-regel blijft qr, ook als het bedrijf nu op PIN staat (besluit 15 okt)
na; sql "set session_replication_role = replica; update approvals set method = 'qr' where receipt_id='$BON'" >/dev/null
ok "r3: wachtende qr-regel bij PIN-bedrijf -> geen PIN-eis, reserveren ongeldig" $([ -z "$(sql "select public.pin_eis('$BON')")" ] && start | grep -q ongeldig && echo 1)
ok "r3: ... en de publieke link (service_role) vergrendelt de bon zonder PIN" $(svc "update receipts set status='locked' where id='$BON' returning id" | grep -q "^a0" && echo 1)
na; sql "set session_replication_role = replica; update approvals set method = 'restaurant_confirms' where receipt_id='$BON'" >/dev/null
ok "r3: wachtende restaurant_confirms-regel -> manager keurt goed zonder PIN" $([ "$(goedkeur)" = "ok 1" ] && echo 1)
na; sql "set session_replication_role = replica; delete from approvals where receipt_id='$BON'" >/dev/null; ok "r3: geen wachtende regel bij PIN-bedrijf -> pin_eis = huidig bedrijf, rechtstreeks goedkeuren geweigerd" $([ "$(sql "select public.pin_eis('$BON')")" = "$A100" ] && goedkeur | grep -q "PIN-goedkeuring ontbreekt" && echo 1)
na; g=$(als $OWN "insert into approvals (receipt_id, company_id, method, status) values ('$BON0','$A100','qr','pending') returning id")
ok "r3: nieuwe regel met andere methode dan het bedrijf (qr bij PIN) -> geweigerd" $(echo "$g" | grep -q "wijkt af" && echo 1) "$g"
g=$(als $OWN "insert into approvals (receipt_id, company_id, method, status) values ('$BON0','$A100','pin','pending') returning id")
ok "r3: nieuwe regel met de methode van het bedrijf -> toegestaan" $([ "$g" = "ok 1" ] && echo 1) "$g"
na; sql "set session_replication_role = replica; insert into approvals (receipt_id, company_id, method, status) values ('$BON','$A100','pin','pending'), ('$BON','$A105','pin','pending')" >/dev/null
ok "r3: PIN-regels van twee bedrijven -> reserveren en goedkeuren beide geweigerd" $(start | grep -qi "ongeldig\|meerdere" && goedkeur | grep -qi "meerdere" && echo 1) "$(start) $(goedkeur)"
# s. goedkeuringsregel
na; sql "set session_replication_role = replica; insert into approvals (id, receipt_id, company_id, method, status) values ('a0000000-0000-0000-0000-000000009998','$BON','$A100','pin','pending')" >/dev/null
g=$(als $MGR "update approvals set status='approved', approved_at=now(), approved_by='x' where id='a0000000-0000-0000-0000-000000009998' returning id")
ok "s: PIN-regel op approved terwijl de bon wacht -> geweigerd" $(echo "$g" | grep -q "pas na goedkeuring" && echo 1) "$g"
i=$(startid); afrond $i true >/dev/null; goedkeur >/dev/null; g=$(als $MGR "update approvals set status='approved', approved_at=now(), approved_by='x' where id='a0000000-0000-0000-0000-000000009998' returning id")
ok "s: na goedkeuring van de bon -> toegestaan" $([ "$g" = "ok 1" ] && echo 1) "$g"
na; sql "set session_replication_role = replica; update approvals set method = 'qr' where receipt_id='$BON'" >/dev/null
g=$(als $MGR "update approvals set status='approved', approved_at=now(), approved_by='x' where receipt_id='$BON' and method='qr' returning id"); ok "s: regel met andere methode ongemoeid (qr-regel goedkeuren mag)" $([ "$g" = "ok 1" ] && echo 1) "$g"
# t. triggervolgorde: ongeldige overgang faalt op receipts_guard, niets verbruikt
na; i=$(startid); afrond $i true >/dev/null; g=$(als $MGR "update receipts set status='approved' where id='$BON0' returning id")
ok "t: ongeldige overgang (linked -> approved) faalt op receipts_guard, niets verbruikt" $(echo "$g" | grep -q "Ongeldige statusovergang" && [ "$(sql "select count(*) from pin_reserveringen where verbruikt_op is not null")" = "0" ] && echo 1) "$g"
# service_role (publieke link) zonder uitzondering
na; g=$(svc "update receipts set status='locked' where id='$BON' returning id"); ok "publieke link (service_role) kan een PIN-bon niet vergrendelen" $(echo "$g" | grep -q "PIN-goedkeuring ontbreekt" && echo 1) "$g"
# afwijzen blijft werken zonder PIN
na; ok "afwijzen (pending_approval -> linked) blijft werken zonder PIN" $([ "$(goedkeur $BON $MGR linked)" = "ok 1" ] && echo 1)

# u. bon indienen in een keer (0041): als de gebruiker (INVOKER), methode uit de instelling, alles of niets
regels() { sql "select count(*)||':'||coalesce(string_agg(method||'/'||coalesce(verification_code,'-'), ','),'') from approvals where receipt_id='${1:-$BON0}' and status='pending'"; }
na; g=$(als $MGR "select public.bon_indienen('$BON0', 'tok-1')")
ok "u: manager dient een linked bon in (PIN-bedrijf): pending_approval + 1 PIN-regel zonder token" $([ "$(bonst $BON0)" = "pending_approval" ] && [ "$(regels)" = "1:pin/-" ] && echo 1) "$g $(bonst $BON0) $(regels)"
g=$(als $MGR "select public.bon_indienen('$BON0', 'tok-2')"); ok "u: tweede keer indienen -> geweigerd, nog steeds 1 regel" $(echo "$g" | grep -q "niet (meer)" && [ "$(regels)" = "1:pin/-" ] && echo 1) "$g"
na; sql "update approval_settings set method='qr' where company_id='$A100'" >/dev/null; als $MGR "select public.bon_indienen('$BON0', 'tok-qr')" >/dev/null
ok "u: QR-bedrijf -> regel qr met token" $([ "$(regels)" = "1:qr/tok-qr" ] && echo 1) "$(regels)"
na; sql "update approval_settings set is_required=false where company_id='$A100'" >/dev/null; g=$($PSQL -d $DB -At -c "begin; select set_config('request.jwt.claim.sub','$MGR',true) is null and set_config('request.jwt.claims','{\"role\":\"authenticated\",\"sub\":\"$MGR\"}',true) is null; set local role authenticated; select coalesce(public.bon_indienen('$BON0', 'x'),'NULL'); commit;" 2>&1 | grep -v '^f$' | grep -v '^$' | tail -1)
ok "u: goedkeuring uit -> null, niets gewijzigd" $([ "$g" = "NULL" ] && [ "$(bonst $BON0)" = "linked" ] && [ "$(regels)" = "0:" ] && echo 1) "$g"
# tenantcontrole: manager van restaurant B dient bon 300 van A in; slaagt (1) alleen als dat geweigerd wordt en er niets verandert
tenant() { local g; g=$(als b0000000-0000-0000-0000-000000000011 "select public.bon_indienen('$BON0', 'x')"); echo "antwoord: $g | bon: $(bonst $BON0) | regels: $(regels)" > $TMP/tenant
  echo "$g" | grep -q "niet gevonden" && [ "$(bonst $BON0)" = "linked" ] && [ "$(regels)" = "0:" ] && echo 1; }
na; t=$(tenant); ok "u: manager van restaurant B -> 'Bon niet gevonden' (RLS geldt), niets gewijzigd" $t "$(cat $TMP/tenant)"
na; g=$(als a0000000-0000-0000-0000-000000000014 "select public.bon_indienen('$BON0', 'x')")
ok "u: keuken (geen recht op bonnen) -> geweigerd, niets gewijzigd" $(echo "$g" | grep -qi "error" && [ "$(bonst $BON0)" = "linked" ] && [ "$(regels)" = "0:" ] && echo 1) "$g"
ok "u: anon en service_role mogen bon_indienen niet uitvoeren" $([ "$(sql "select has_function_privilege('anon','public.bon_indienen(uuid,text)','execute')::text || has_function_privilege('service_role','public.bon_indienen(uuid,text)','execute')::text")" = "falsefalse" ] && echo 1)
na; sql "create function public.tmp_fout() returns trigger language plpgsql as \$x\$ begin raise exception 'testfout regel'; end \$x\$; create trigger zz_tmp_fout before insert on public.approvals for each row execute function public.tmp_fout()" >/dev/null
g=$(als $MGR "select public.bon_indienen('$BON0', 'x')"); ok "u: regel aanmaken faalt -> bon blijft linked (alles of niets)" $(echo "$g" | grep -q "testfout" && [ "$(bonst $BON0)" = "linked" ] && [ "$(regels)" = "0:" ] && echo 1) "$g"
# gelijktijdig met een instellingwijziging, beide volgordes; en met een verbreed venster (slaap tussen lezen en regel) -> weigering, niets half
na; ( $PSQL -d $DB -c "begin; update approval_settings set method='qr' where company_id='$A100'; select pg_sleep(1.2); commit;" >/dev/null 2>&1 ) &
sleep 0.3; g=$(als $MGR "select public.bon_indienen('$BON0', 'tok-c')"); wait
ok "u: wijziging eerst (nog open), indienen tegelijk -> 1 regel met een geldige methode, nooit half" $([ "$(bonst $BON0)" = "pending_approval" ] && echo "$(regels)" | grep -q "^1:\(pin/-\|qr/tok-c\)$" && echo 1) "$g $(regels)"
na; ( $PSQL -d $DB -c "begin; select set_config('request.jwt.claim.sub','$MGR',true); set local role authenticated; select public.bon_indienen('$BON0', 'tok-d'); select pg_sleep(1.2); commit;" >/dev/null 2>&1 ) &
sleep 0.3; $PSQL -d $DB -c "update approval_settings set method='qr' where company_id='$A100'" >/dev/null 2>&1; wait
ok "u: indienen eerst (nog open), wijziging tegelijk -> 1 PIN-regel, instelling daarna qr" $([ "$(bonst $BON0)" = "pending_approval" ] && [ "$(regels)" = "1:pin/-" ] && [ "$(sql "select method from approval_settings where company_id='$A100'")" = "qr" ] && echo 1) "$(regels)"
na; muteer "public.bon_indienen(uuid,text)" "if not coalesce(aan, false)" "perform pg_sleep(1); if not coalesce(aan, false)"
( sleep 0.3; $PSQL -d $DB -c "update approval_settings set method='qr' where company_id='$A100'" >/dev/null 2>&1 ) &
g=$(als $MGR "select public.bon_indienen('$BON0', 'x')"); wait
ok "u: instelling wijzigt precies tussen lezen en regel -> geweigerd ('wijkt af'), bon blijft linked, geen regel" $(echo "$g" | grep -q "wijkt af" && [ "$(bonst $BON0)" = "linked" ] && [ "$(regels)" = "0:" ] && echo 1) "$g"
# mutatie: dezelfde tenantcontrole moet nu FALEN (verwacht: geen weigering, bon van A staat op pending_approval met een regel)
na; sql "alter function public.bon_indienen(uuid,text) security definer" >/dev/null; t=$(tenant)
ok "mutatie bon_indienen als DEFINER: de tenantcontrole faalt (verwacht en gemeten: $(cat $TMP/tenant))" $([ -z "$t" ] && [ "$(bonst $BON0)" = "pending_approval" ] && echo 1) "$(cat $TMP/tenant)"

# 5. parallelle eigenschapstest
para() {  # $1 = aantal rondes, $2 = (optioneel) opdracht na elke verse kopie, bv. een mutatie
  local bad=0 d0 d1 lt=0
  d0=$(sql "select deadlocks from pg_stat_database where datname = current_database()")
  for r in $(seq 1 $1); do
    na; [ -n "${2:-}" ] && eval "$2"; local reset=$((r % 3 == 0))
    for k in $(seq 1 30); do (
      o=$($PSQL -d $DB -At -c "set lock_timeout = '5s'; begin; set local role service_role; select public.pin_poging_start('$A100','$BON')->>'id'; commit;" 2>&1 | grep -v '^$' | tail -1)
      echo "start $o" >> $TMP/p$r.$k
      if [[ "$o" =~ ^[0-9a-f-]{36}$ ]]; then
        sleep 0.0$((RANDOM % 9)); m=$((k % 5))
        if [ $m = 0 ]; then a=$($PSQL -d $DB -At -c "set lock_timeout='5s'; begin; set local role service_role; select public.pin_poging_afronden('$o', true); commit;" 2>&1 | tail -1); echo "af $o $a" >> $TMP/p$r.$k
          if [ "$a" = ok ]; then $PSQL -d $DB -At -c "set lock_timeout='5s'; begin; select set_config('request.jwt.claim.sub','$MGR',true); set local role authenticated; update receipts set status='approved' where id='$BON' and status='pending_approval'; commit;" >> $TMP/p$r.$k 2>&1; fi
        elif [ $m = 1 ]; then :   # crash: nooit afronden
        else a=$($PSQL -d $DB -At -c "set lock_timeout='5s'; begin; set local role service_role; select public.pin_poging_afronden('$o', false); commit;" 2>&1 | tail -1); echo "af $o $a" >> $TMP/p$r.$k
             [ $m = 2 ] && { a2=$($PSQL -d $DB -At -c "begin; set local role service_role; select public.pin_poging_afronden('$o', true); commit;" 2>&1 | tail -1); echo "af2 $o $a2" >> $TMP/p$r.$k; }
        fi
      fi ) & done
    [ $reset = 1 ] && ( sleep 0.0$((RANDOM % 9)); $PSQL -d $DB -c "set lock_timeout='5s'; update approval_settings set pin_hash = md5(random()::text) where company_id = '$A100'" >/dev/null 2>&1 ) &
    wait
    cat $TMP/p$r.* > $TMP/r$r 2>/dev/null
    # eigenschappen uit de tabel
    local e; e=$(sql "select (select coalesce(max(n),0) from (select count(*) n from pin_reserveringen where status in ('lopend','fout') group by generatie) x) <= 5
      and not exists (select 1 from receipts r where r.id='$BON' and r.status in ('approved','locked')
                      and not exists (select 1 from pin_reserveringen p where p.receipt_id=r.id and p.verbruikt_op is not null))
      and (select count(*) from pin_reserveringen where verbruikt_op is not null) <= 1")
    # eigenschappen uit de terugkoppeling: hooguit één ok per id; tweede afronden nooit ok; geen lock_timeout
    local dub; dub=$(grep -h '^af ' $TMP/r$r | awk '$3=="ok"{print $2}' | sort | uniq -d | wc -l)
    local af2; af2=$(grep -h '^af2 ' $TMP/r$r | awk '$3=="ok"' | wc -l)
    local to; to=$(grep -hi "lock timeout\|deadlock" $TMP/r$r | wc -l); lt=$((lt + to))
    if [ "$e" != "t" ] || [ "$dub" != "0" ] || [ "$af2" != "0" ] || [ "$to" != "0" ]; then bad=$((bad+1)); echo "  ronde $r: tabel=$e dubbel=$dub af2=$af2 timeouts=$to"; fi
  done
  d1=$($PSQL -d postgres -At -c "select sum(deadlocks) from pg_stat_database")
  echo "$bad $lt"
}
D0=$($PSQL -d postgres -At -c "select sum(deadlocks) from pg_stat_database")
uit=$(para $RONDES); D1=$($PSQL -d postgres -At -c "select sum(deadlocks) from pg_stat_database")
ok "parallel: $RONDES rondes x 30 sessies (+ PIN-wijziging in 1 op 3): eigenschappen golden in elke ronde, geen time-outs" $([ "$(echo "$uit" | tail -1)" = "0 0" ] && echo 1) "$uit"
ok "parallel: geen deadlocks (teller pg_stat_database $D0 -> $D1)" $([ "$D0" = "$D1" ] && echo 1)

# 6. bewust kapotte versies: moeten gevangen worden
uit=$(para 3 'muteer "public.pin_poging_start(uuid,uuid)" "for update;" ";"; muteer "public.pin_poging_start(uuid,uuid)" "if n >= 5 then" "perform pg_sleep(0.05); if n >= 5 then"'); ok "mutatie zonder slot (for update weg, racevenster verbreed): parallelle test vangt het" $([ "$(echo "$uit" | tail -1 | cut -d' ' -f1)" != "0" ] && echo 1) "$uit"
na; muteer "public.pin_poging_afronden(uuid,boolean)" "where id = p_id;
  return 'ok';" "where id = p_id;
  if p_juist then update pin_reserveringen set status = 'juist' where company_id = r.company_id and status in ('lopend','fout'); end if;
  return 'ok';"
for k in 1 2 3 4 5; do ids[$k]=$(startid); done; afrond ${ids[1]} true >/dev/null
ok "mutatie 'juist zet de telling op 0' (v1-ontwerp): telling niet meer 4 (a vangt)" $([ "$(telling)" != "4" ] && echo 1) "$(telling)"
na; muteer "public.pin_poging_afronden(uuid,boolean)" "if r.status <> 'lopend' then return 'al_afgerond'; end if;" ""
i=$(startid); afrond $i true >/dev/null; ok "mutatie zonder status-voorwaarde: dubbel afronden geeft tweede 'ok' (c vangt)" $([ "$(afrond $i true)" = "ok" ] && echo 1)
na; muteer "public.pin_poging_afronden(uuid,boolean)" "if r.generatie <> g then" "if false then"
i=$(startid); pinwissel >/dev/null; ok "mutatie zonder generatiecontrole bij afronden: 'ok' na PIN-wijziging (d vangt)" $([ "$(afrond $i true)" = "ok" ] && echo 1)
na; muteer "public.receipts_pin_wacht()" "and generatie = g and status" "and status"
i=$(startid); afrond $i true >/dev/null; pinwissel >/dev/null; ok "mutatie wacht zonder generatiecontrole: goedkeuring na PIN-wijziging slaagt (i vangt)" $([ "$(goedkeur)" = "ok 1" ] && echo 1)
na; muteer "public.receipts_pin_wacht()" "where receipt_id = new.id and company_id = c and" "where company_id = c and"
sql "set session_replication_role = replica; update receipts set status='pending_approval' where id='$BON0'" >/dev/null
i=$(startid); afrond $i true >/dev/null; ok "mutatie wacht zonder bon-koppeling: andere bon goedgekeurd (k vangt)" $([ "$(goedkeur $BON0)" = "ok 1" ] && echo 1)
na; muteer "public.receipts_pin_wacht()" "update pin_reserveringen set verbruikt_op = clock_timestamp() where id = v;" ""
i=$(startid); afrond $i true >/dev/null; goedkeur >/dev/null; ok "mutatie wacht zonder verbruik: reservering na goedkeuring onverbruikt (h vangt)" $([ "$(sql "select verbruikt_op is null from pin_reserveringen where id='$i'")" = "t" ] && echo 1)
na; muteer "public.receipts_pin_wacht()" "and afgerond_op > clock_timestamp() - interval '2 minutes'" ""
i=$(startid); afrond $i true >/dev/null; sql "update pin_reserveringen set afgerond_op = clock_timestamp() - interval '121 seconds' where id='$i'" >/dev/null
ok "mutatie wacht zonder 2-minutengrens: oude juist-reservering keurt goed (k vangt)" $([ "$(goedkeur)" = "ok 1" ] && echo 1)
na; muteer "public.receipts_pin_wacht()" "c := pin_eis(new.id);" "c := pin_eis(new.id); if coalesce(current_setting('request.jwt.claims', true)::json->>'role', '') = 'service_role' then return new; end if;"
ok "mutatie wacht met service_role-uitzondering: publieke link vergrendelt PIN-bon (vangt)" $(svc "update receipts set status='locked' where id='$BON' returning id" | grep -q "^a0" && echo 1)
na; sql "drop trigger approvals_pin_wacht on public.approvals" >/dev/null; sql "set session_replication_role = replica; insert into approvals (id, receipt_id, company_id, method, status) values ('a0000000-0000-0000-0000-000000009998','$BON','$A100','pin','pending')" >/dev/null
ok "mutatie zonder approvals-wacht: PIN-regel op approved terwijl de bon wacht (s vangt)" $([ "$(als $MGR "update approvals set status='approved', approved_at=now(), approved_by='x' where id='a0000000-0000-0000-0000-000000009998' returning id")" = "ok 1" ] && echo 1)
na; muteer "public.approvals_pin_wacht()" "if new.method is distinct from" "if false and new.method is distinct from"
ok "mutatie zonder methodecontrole op nieuwe regel: qr-regel bij PIN-bedrijf toegestaan (r3 vangt)" $([ "$(als $OWN "insert into approvals (receipt_id, company_id, method, status) values ('$BON0','$A100','qr','pending') returning id")" = "ok 1" ] && echo 1)
na; muteer "public.approval_settings_pin_wacht()" "generatie = generatie + 1, " ""
i=$(startid); pinwissel >/dev/null; ok "mutatie PIN-wacht zonder generatie + 1: oude reservering 'ok' na PIN-wijziging (l vangt)" $([ "$(afrond $i true)" = "ok" ] && echo 1)
na; muteer "public.pin_poging_afronden(uuid,boolean)" "if not found then return 'onbekend'; end if;
  select generatie" "if not found then return 'ok'; end if;
  select generatie"
ok "mutatie onbekend id = ok (m vangt)" $([ "$(afrond 00000000-0000-0000-0000-000000000099 true)" = "ok" ] && echo 1)
na; muteer "public.pin_poging_start(uuid,uuid)" "t := clock_timestamp();" "t := now();"
( $PSQL -d $DB -c "begin; set local role service_role; select pg_sleep(0.6); select public.pin_poging_start('$A100','$BON'); commit;" >/dev/null 2>&1 ) &
sleep 0.2; ( $PSQL -d $DB -c "begin; set local role service_role; select public.pin_poging_start('$A100','$BON'); select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) & wait
ok "mutatie now() i.p.v. clock_timestamp(): wachter krijgt een eerdere tijd (g vangt)" $([ "$(sql "select (max(gemaakt_op) - min(gemaakt_op)) > interval '1 second' from pin_reserveringen")" = "f" ] && echo 1)
na; sql "set session_replication_role = replica; delete from approvals where receipt_id='$BON'" >/dev/null; muteer "public.receipts_pin_wacht()" "perform 1 from open_tabs where id = old.open_tab_id for share;" ""
TAB=$(sql "select open_tab_id from receipts where id='$BON'"); sql "set session_replication_role = replica; update open_tabs set company_id='$A105' where id='$TAB'" >/dev/null
( $PSQL -d $DB -c "begin; set local session_replication_role = replica; update open_tabs set company_id='$A100' where id='$TAB'; select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
sleep 0.4; g=$(goedkeur); wait
ok "mutatie wacht zonder for share: goedkeuring tijdens wissel naar PIN-bedrijf slaagt zonder PIN (r2 vangt)" $([ "$g" = "ok 1" ] && echo 1) "$g"
na; muteer "public.pin_poging_start(uuid,uuid)" "if st is distinct from 'pending_approval' or pin_eis(p_bon) is distinct from p_company then" "if false then"
ok "mutatie start zonder bon- en eiscontrole: reservering voor verkeerd bedrijf toegelaten (r vangt)" $(start $A105 $BON | grep -q "^true" && echo 1)
na; sql "grant execute on function public.pin_poging_start(uuid,uuid) to authenticated" >/dev/null
ok "mutatie functie uitvoerbaar voor authenticated: harnas PQ06 vangt" $([ "$(sql "select result from hardening_test.run(14) where id='PQ06'")" = "FAIL" ] && echo 1)

echo "== $pass geslaagd, $fail mislukt"
$PSQL -d postgres -c "drop database if exists $DB" -c "drop database if exists pp_na" >/dev/null 2>&1
[ $fail = 0 ]
