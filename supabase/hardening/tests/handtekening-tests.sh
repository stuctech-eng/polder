#!/usr/bin/env bash
# Tests voor stap 14c (migraties 0043-0048: handtekening van de klant): heen en terug stap voor stap, controleblok, rechten,
# misbruik van de markering, fouten, gelijktijdigheid, bestaande methoden en bewust kapotte versies. ALLEEN lokaal; maakt en
# verwijdert eigen kopie-databases.
# Gebruik:  PSQL="psql -X -q -h /socketdir -p <poort> -U postgres" BASIS=<database t/m 0042, met seed en harnas> bash handtekening-tests.sh
set -uo pipefail
PSQL=${PSQL:-"psql -X -q"}; BASIS=${BASIS:?BASIS = database t/m 0042}
cd "$(dirname "$0")/../.."          # = supabase/
MIG=(migrations/0043_handtekening_module.sql migrations/0044_handtekening_bonwacht.sql migrations/0045_handtekening_regelwacht.sql
     migrations/0046_handtekening_teken_wacht.sql migrations/0047_bon_ondertekenen.sql migrations/0048_bon_ondertekenen_recht.sql)
RB=(rollbacks/0043_rollback.sql rollbacks/0044_rollback.sql rollbacks/0045_rollback.sql rollbacks/0046_rollback.sql rollbacks/0047_rollback.sql
    rollbacks/0048_rollback.sql)
C=hardening/prod-teken14c-checks.sql
CF=hardening/prod-teken14c-functie.sql
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
RA=a0000000-0000-0000-0000-000000000001; A100=a0000000-0000-0000-0000-000000000100
BON=a0000000-0000-0000-0000-000000000301; BON0=a0000000-0000-0000-0000-000000000300; REGEL=a0000000-0000-0000-0000-000000000400
OWN=a0000000-0000-0000-0000-000000000010; MGR=a0000000-0000-0000-0000-000000000011; ADM=a0000000-0000-0000-0000-000000000012
BED=a0000000-0000-0000-0000-000000000013; KEU=a0000000-0000-0000-0000-000000000014; UIT=a0000000-0000-0000-0000-000000000015
BEDB=b0000000-0000-0000-0000-000000000013
# echte PNG als data-URL: pngurl <breedte> <hoogte> [soort] [precieze lengte van de data-URL]
#   soort: ok | zonder_iend | ihdr_kapot | geen_png (base64 van tekst) | handtekening_kapot | spatie (witruimte in de base64)
pngurl() { python3 - "$@" <<'E'
import sys, zlib, struct, base64
w, h = int(sys.argv[1]), int(sys.argv[2]); soort = sys.argv[3] if len(sys.argv) > 3 else "ok"; doel = int(sys.argv[4]) if len(sys.argv) > 4 else 0
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
def maak(extra):
    kop = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDX" if soort == "ihdr_kapot" else b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
    if soort == "handtekening_kapot": kop = b"\x88" + kop[1:]
    rest = (chunk(b"tEXt", b"x\x00" + b"y" * extra) if extra else b"") + chunk(b"IDAT", zlib.compress(b"\x00" * 4)) + (b"" if soort == "zonder_iend" else chunk(b"IEND", b""))
    return kop + rest
b = maak(0)
if doel:
    n = (doel - 22) // 4 * 3; b = maak(n - len(maak(0)) - 14)   # tEXt-blok vult aan tot precies n bytes (geen opvulling in base64)
d = base64.b64encode(b"hallo wereld, dit is geen plaatje " * 5).decode() if soort == "geen_png" else base64.b64encode(b).decode()
if soort == "spatie": d = d[:40] + " " + d[40:]
print("data:image/png;base64," + d)
E
}
SIG=$(pngurl 300 120)
DB=hk_test
pass=0; fail=0
ok()   { if [ "${2:-}" = "1" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
vers() { $PSQL -d postgres -c "drop database if exists $DB" -c "create database $DB template ${1:-$BASIS}" >/dev/null 2>&1; }
run()  { $PSQL -d $DB -c "$(cat "$1")" 2>&1; }
sql()  { $PSQL -d $DB -At -c "$1" 2>/dev/null | tail -1; }
check(){ $PSQL -d $DB -At -F'|' -f $C 2>&1 | grep -v '^$' | head -1; }
fails(){ sql "select count(*) from hardening_test.run($1) where result = 'FAIL'"; }
faillijst(){ sql "select coalesce(string_agg(id, ',' order by id), '') from hardening_test.run($1) where result = 'FAIL'"; }
claims(){ echo "select set_config('request.jwt.claim.sub','$1',true) is null and set_config('request.jwt.claims','{\"role\":\"authenticated\",\"sub\":\"$1\"}',true) is null;"; }
# als ingelogde gebruiker $1: geeft de laatste uitvoerregel of de foutmelding
als()  { local o; o=$($PSQL -d $DB -At -c "begin; $(claims $1) set local role authenticated; $2; commit;" 2>&1 | grep -v '^$' | grep -v '^f$')
         if echo "$o" | grep -q ERROR; then echo "$o" | grep ERROR | head -1; else echo "$o" | tail -1; fi; }
# als postgres (zoals een andere SECURITY DEFINER-functie of de SQL-editor), met de sessie van gebruiker $1
pg()   { local o; o=$($PSQL -d $DB -At -c "begin; $(claims $1) $2; commit;" 2>&1 | grep -v '^$' | grep -v '^f$')
         if echo "$o" | grep -q ERROR; then echo "$o" | grep ERROR | head -1; else echo "$o" | tail -1; fi; }
rol()  { local o; o=$($PSQL -d $DB -At -c "begin; set local role $1; $2; commit;" 2>&1 | grep -v '^$')
         if echo "$o" | grep -q ERROR; then echo "$o" | grep ERROR | head -1; else echo "$o" | tail -1; fi; }
vinger(){ als ${2:-$BED} "select public.bon_vingerafdruk('${1:-$BON}')"; }
teken(){ local fp=${4:-$(vinger ${1:-$BON} ${2:-$BED})}; als ${2:-$BED} "select public.bon_ondertekenen('${1:-$BON}', '${3:-Jan Klant}', '${5:-$SIG}', '$fp')"; }
bonst(){ sql "select status from receipts where id='${1:-$BON}'"; }
regel(){ sql "select status || '|' || coalesce(approved_by,'') || '|' || (signature_data is not null) from approvals where receipt_id='${1:-$BON}' order by created_at desc limit 1"; }
# opzet: module aan voor restaurant A, bedrijf A100 methode signature, bon 301 wacht met een handtekeningregel
opzet(){ $PSQL -d $DB -c "set session_replication_role = replica; insert into restaurant_features values ('$RA','signature',true,now());
  update approval_settings set method='signature', is_required=true where company_id='$A100';
  update approvals set method='signature', verification_code=null where id='$REGEL'" >/dev/null; }
muteer() { $PSQL -d $DB -At -c "select pg_get_functiondef('$1'::regprocedure)" > $TMP/f.sql
  python3 - $TMP/f.sql "$2" "$3" <<'E'
import sys; p, o, n = sys.argv[1:4]; s = open(p).read(); assert s.count(o) == 1, "mutatie niet uniek: " + o; open(p, 'w').write(s.replace(o, n))
E
  $PSQL -d $DB -c "$(cat $TMP/f.sql)" >/dev/null 2>&1 || echo "MUTATIE FAALDE"; }
alle_mig(){ for f in "${MIG[@]}"; do run $f >/dev/null; done; }
na(){ vers; alle_mig; opzet; }

echo "== PostgreSQL $($PSQL -d postgres -At -c 'show server_version')"
ok "14 blokken passen in de editor (< 3000 tekens)" $(for f in "${MIG[@]}" "${RB[@]}" $C $CF; do [ "$(wc -c < $f)" -lt 3000 ] || exit; done; echo 1)

# 1. uitgangsstand en volgorde
vers; c0=$(check); m0=$(echo "$c0" | cut -d'|' -f6)
ok "uitgangsstand: controleblok 0042|000000|t|0|d84e54,9d3540" $([ "$(echo "$c0" | cut -d'|' -f1-5)" = "0042|000000|t|0|d84e54,9d3540" ] && echo 1) "$c0"
src0=$(sql "select md5(string_agg(prosrc, '|' order by proname)) from pg_proc where proname in ('receipts_guard','approvals_guard')")
B=$([ "$(sql "select has_table_privilege('authenticated','public.contacts','select')")" = "f" ] && echo 13 || echo 12)
F14=$(faillijst 14); FB=$(faillijst $B)
echo "== basis: harnas run($B) FAIL=[$FB], run(14) FAIL=[$F14]"
for i in 1 2 3 4 5; do out=$(run ${MIG[$i]}); ok "$(basename ${MIG[$i]}) zonder voorganger: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "vooraf" && [ "$(check)" = "$c0" ] && echo 1) "$out"; done
for i in 0 1 2 3 4 5; do out=$(run ${RB[$i]}); ok "$(basename ${RB[$i]}) zonder migratie: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "rollback vooraf" && [ "$(check)" = "$c0" ] && echo 1) "$out"; done

# 2. heen, stap voor stap
STANDEN=(0043 0044 0045 0046 0047 0048); BITS=(100000 110000 111000 111100 111110 111111); W=(0 0 0 2 2 2)
WM=("d84e54,9d3540" "d84e54,50feb6" "f09a66,50feb6" "f09a66,50feb6" "f09a66,50feb6" "f09a66,50feb6")
for i in 0 1 2 3 4 5; do
  out=$(run ${MIG[$i]}); c=$(check)
  ok "$(basename ${MIG[$i]}) slaagt; controleblok ${STANDEN[$i]}|${BITS[$i]}|t|${W[$i]}|${WM[$i]}, bestaand_md5 gelijk" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(echo "$c" | cut -d'|' -f1-5)" = "${STANDEN[$i]}|${BITS[$i]}|t|${W[$i]}|${WM[$i]}" ] && [ "$(echo "$c" | cut -d'|' -f6)" = "$m0" ] && echo 1) "$out $c"
  out=$(run ${MIG[$i]}); ok "$(basename ${MIG[$i]}) tweede keer: afgebroken, niets gewijzigd" $(echo "$out" | grep -q "vooraf" && [ "$(check)" = "$c" ] && echo 1) "$out"
done
ok "harnas na 0043-0048: run($B) en run(14) precies als vooraf" $([ "$(faillijst $B)" = "$FB" ] && [ "$(faillijst 14)" = "$F14" ] && echo 1) "$(faillijst $B) / $(faillijst 14)"
ok "module signature: overal uit (standaard)" $([ "$(sql "select count(*) from restaurants where public.feature_aan(id, 'signature')")" = "0" ] && echo 1)
ok "triggervolgorde receipts: ... receipts_guard, receipts_pin_wacht, receipts_teken_wacht ..." $([ "$(sql "select string_agg(tgname, ',' order by tgname) from pg_trigger where tgrelid = 'public.receipts'::regclass and not tgisinternal")" = "module_wacht,receipts_guard,receipts_pin_wacht,receipts_teken_wacht,xref_keys_immutable,xref_receipts,xref_user_ref" ] && echo 1)
ok "triggervolgorde approvals: approvals_guard, approvals_pin_wacht, approvals_teken_wacht, ..." $([ "$(sql "select string_agg(tgname, ',' order by tgname) from pg_trigger where tgrelid = 'public.approvals'::regclass and not tgisinternal")" = "approvals_guard,approvals_pin_wacht,approvals_teken_wacht,module_wacht,xref_approvals" ] && echo 1)
ok "markering: alleen bon_ondertekenen zet hem (set_config), 4 functies lezen hem" $([ "$(sql "select string_agg(proname, ',' order by proname) from pg_proc where prosrc like '%set_config(''polder.ondertekening''%'")" = "bon_ondertekenen" ] && [ "$(sql "select count(*) from pg_proc where prosrc like '%polder.ondertekening%'")" = "4" ] && echo 1)

# 3. terug, stap voor stap, exact
for i in 5 4 3 2 1 0; do out=$(run ${RB[$i]}); ok "$(basename ${RB[$i]}) slaagt, bestaand_md5 gelijk" $([ -z "$(echo "$out" | grep -i error)" ] && [ "$(check | cut -d'|' -f6)" = "$m0" ] && echo 1) "$out"; done
ok "na alle rollbacks: controleblok exact als vooraf" $([ "$(check)" = "$c0" ] && echo 1) "$(check)"
ok "na alle rollbacks: tekst van receipts_guard en approvals_guard byte voor byte als vooraf" $([ "$(sql "select md5(string_agg(prosrc, '|' order by proname)) from pg_proc where proname in ('receipts_guard','approvals_guard')")" = "$src0" ] && echo 1)
ok "na alle rollbacks: harnas als vooraf" $([ "$(faillijst $B)" = "$FB" ] && [ "$(faillijst 14)" = "$F14" ] && echo 1)
alle_mig; ok "opnieuw heen na rollback: slaagt (0048)" $([ "$(check | cut -d'|' -f1)" = "0048" ] && echo 1)
opzet; teken >/dev/null; out=$(run ${RB[0]}); ok "0043 rollback weigert als er al een handtekening is (eerst beoordelen)" $(echo "$out" | grep -q "rollback vooraf" && echo 1) "$out"

# 4. de ondertekening zelf
na; fp=$(vinger); r=$(teken)
ok "bediening laat tekenen: locked, regel approved door de klant, handtekening opgeslagen" $([ "$r" = "locked" ] && [ "$(bonst)" = "locked" ] && [ "$(regel)" = "approved|Jan Klant|true" ] && echo 1) "$r $(bonst) $(regel)"
ok "metadata: gestart door de bediening, met vingerafdruk" $([ "$(sql "select metadata->>'gestart_door' = '$BED' and metadata->>'vingerafdruk' = '$fp' from approvals where id='$REGEL'")" = "t" ] && echo 1)
ok "tweede keer tekenen: geweigerd (wacht niet meer)" $(teken | grep -q "wacht niet" && echo 1)
na; sql "set session_replication_role = replica; update approval_settings set auto_lock = false where company_id='$A100'" >/dev/null
ok "auto_lock uit: bon wordt approved (niet locked)" $([ "$(teken)" = "approved" ] && [ "$(bonst)" = "approved" ] && echo 1)
na; r=$(pg $BED "select public.bon_ondertekenen('$BON','Jan Klant','$SIG',public.bon_vingerafdruk('$BON')); select coalesce(nullif(current_setting('polder.ondertekening', true), ''), '<leeg>')")
ok "markering is direct na de functie leeg (zelfde transactie)" $([ "$r" = "<leeg>" ] && [ "$(bonst)" = "locked" ] && echo 1) "[$r]"
na; for n in "J" "$(python3 -c "print('x'*101)")" "   "; do r=$(teken $BON $BED "$n"); ok "naam '${n:0:12}...' geweigerd, niets gewijzigd" $(echo "$r" | grep -q "Naam ongeldig" && [ "$(bonst)" = "pending_approval" ] && echo 1) "$r"; done
# 4b. echte PNG-controle (png_geldig, 0048): eerst de functie zelf, daarna via bon_ondertekenen
geldig() { $PSQL -d $DB -At -f "$1" 2>&1 | tail -1; }
pngsql() { echo "select public.png_geldig('$1')" > $TMP/png.sql; geldig $TMP/png.sql; }
ok "png_geldig: echte PNG 300x120 = waar; 1x1 = waar; met IEND en zelfde lengte (400) als de afgekapte = waar" $([ "$(pngsql "$SIG")" = "t" ] && [ "$(pngsql "$(pngurl 1 1)")" = "t" ] && [ "$(pngsql "$(pngurl 10 10 ok 400)")" = "t" ] && echo 1)
for g in "ongeldige base64 (201 x A)|data:image/png;base64,$(python3 -c "print('A'*201)")" \
         "geldige base64, geen PNG|$(pngurl 10 10 geen_png)" "PNG zonder IEND (afgekapt)|$(pngurl 10 10 zonder_iend 400)" \
         "eerste blok is geen IHDR|$(pngurl 10 10 ihdr_kapot)" "PNG-handtekening beschadigd|$(pngurl 10 10 handtekening_kapot)" \
         "witruimte in de base64|$(pngurl 10 10 spatie)" "breedte 0|$(pngurl 0 10)" "hoogte 0|$(pngurl 10 0)" \
         "breedte 2049|$(pngurl 2049 10)" "hoogte 1025|$(pngurl 10 1025)" "breedte 70000 (groter dan 2 bytes)|$(pngurl 70000 10)" \
         "jpeg-voorvoegsel|$(pngurl 10 10 | sed 's#image/png#image/jpeg#')" "geen data-URL|$(pngurl 10 10 | sed 's#^data:image/png;base64,##')"; do
  ok "png_geldig weigert: ${g%%|*}" $([ "$(pngsql "${g#*|}")" = "f" ] && echo 1) "$(pngsql "${g#*|}")"; done
ok "png_geldig grens afmetingen: 2048x1024 = waar" $([ "$(pngsql "$(pngurl 2048 1024)")" = "t" ] && echo 1)
GROOT=$(pngurl 100 50 ok 199998); TEGROOT=$(pngurl 100 50 ok 200002)
ok "png_geldig grens grootte: geldige PNG van ${#GROOT} tekens = waar, van ${#TEGROOT} tekens = onwaar" $([ "${#GROOT}" = "199998" ] && [ "${#TEGROOT}" = "200002" ] && [ "$(pngsql "$GROOT")" = "t" ] && [ "$(pngsql "$TEGROOT")" = "f" ] && echo 1) "${#GROOT} ${#TEGROOT}"
ok "png_geldig(null) = onwaar (niet leeg)" $([ "$(sql "select public.png_geldig(null)")" = "f" ] && echo 1)
for g in "ongeldige base64|data:image/png;base64,$(python3 -c "print('A'*201)")" "geen PNG|$(pngurl 10 10 geen_png)" "breedte 2049|$(pngurl 2049 10)"; do
  r=$(teken $BON $BED "Jan" "" "${g#*|}"); ok "bon_ondertekenen weigert ${g%%|*}, niets gewijzigd" $(echo "$r" | grep -q "Geen PNG" && [ "$(bonst)" = "pending_approval" ] && echo 1) "$r"; done
echo "begin; $(claims $BED) set local role authenticated; select public.bon_ondertekenen('$BON','Jan','$TEGROOT',public.bon_vingerafdruk('$BON')); commit;" > $TMP/groot.sql
r=$($PSQL -d $DB -At -f $TMP/groot.sql 2>&1 | grep -m1 ERROR); ok "bon_ondertekenen weigert een geldige PNG boven 200000 tekens" $(echo "$r" | grep -q "Geen PNG" && [ "$(bonst)" = "pending_approval" ] && echo 1) "$r"
echo "begin; $(claims $BED) set local role authenticated; select public.bon_ondertekenen('$BON','Jan','$GROOT',public.bon_vingerafdruk('$BON')); commit;" > $TMP/groot.sql
r=$($PSQL -d $DB -At -f $TMP/groot.sql 2>&1 | grep -v '^f$' | tail -1); ok "bon_ondertekenen neemt een geldige PNG van 199998 tekens aan, volledig opgeslagen" $([ "$r" = "locked" ] && [ "$(sql "select length(signature_data) from approvals where id='$REGEL'")" = "199998" ] && echo 1) "$r"
na
r=$(teken $BON $BED "Jan" "00000000000000000000000000000000"); ok "verkeerde vingerafdruk: geweigerd, niets gewijzigd" $(echo "$r" | grep -q "gewijzigd" && [ "$(bonst)" = "pending_approval" ] && echo 1) "$r"
# vingerafdruk van een oude ronde: afgewezen en opnieuw ingediend = nieuwe regel = andere vingerafdruk
fp=$(vinger); als $MGR "update receipts set status='linked' where id='$BON'; update approvals set status='rejected' where id='$REGEL'" >/dev/null
r1=$(als $BED "select public.bon_indienen('$BON', 'x')"); r=$(teken $BON $BED "Jan" "$fp")
ok "afgewezen + opnieuw ingediend: oude vingerafdruk geweigerd, nieuwe werkt" $([ "$r1" = "signature" ] && echo "$r" | grep -q "gewijzigd" && [ "$(teken)" = "locked" ] && echo 1) "$r1 $r"

# 4c. bedrijf van de rekening = bedrijf van de regel (rekening 204 heeft geen afdeling, dus het bedrijf kan wisselen)
T4=a0000000-0000-0000-0000-000000000204; B2=a0000000-0000-0000-0000-000000009001; A105=a0000000-0000-0000-0000-000000000105
opzet_b2() { sql "set session_replication_role = replica; insert into receipts (id, restaurant_id, open_tab_id, status, total, receipt_number) values ('$B2','$RA','$T4','pending_approval',9,'W-1');
  insert into approvals (receipt_id, company_id, method, status) values ('$B2','$A100','signature','pending')" >/dev/null; }
wissel() { als $OWN "update open_tabs set company_id='${1:-$A105}' where id='$T4' returning id" >/dev/null; }
regel2() { sql "select status || '|' || company_id from approvals where receipt_id='$B2'"; }
na; opzet_b2; fp=$(vinger $B2); wissel; fp2=$(vinger $B2)
ok "vingerafdruk verandert als het bedrijf van de rekening wijzigt" $([ -n "$fp" ] && [ "$fp" != "$fp2" ] && echo 1) "$fp $fp2"
r=$(teken $B2 $BED "Jan" "$fp"); ok "bedrijf gewijzigd voor het tekenen, oude vingerafdruk: geweigerd, niets gewijzigd" $(echo "$r" | grep -q "Bedrijf verschilt\|gewijzigd" && [ "$(bonst $B2)" = "pending_approval" ] && [ "$(regel2)" = "pending|$A100" ] && echo 1) "$r"
r=$(teken $B2 $BED "Jan" "$fp2"); ok "bedrijf gewijzigd, vingerafdruk van na de wissel: geweigerd (bedrijf verschilt), niets gewijzigd" $(echo "$r" | grep -q "Bedrijf verschilt" && [ "$(bonst $B2)" = "pending_approval" ] && [ "$(regel2)" = "pending|$A100" ] && echo 1) "$r"
wissel $A100; ok "bedrijf weer terug: tekenen lukt" $([ "$(teken $B2)" = "locked" ] && [ "$(regel2)" = "approved|$A100" ] && echo 1)
# gelijktijdig: de bedrijfswissel loopt (nog niet vastgelegd) terwijl getekend wordt -> tekenen wacht op de rekening en weigert daarna
na; opzet_b2; fp=$(vinger $B2)
( $PSQL -d $DB -At -c "begin; $(claims $OWN) set local role authenticated; update open_tabs set company_id='$A105' where id='$T4'; select pg_sleep(1.5); commit;" > $TMP/w1 2>&1 ) &
sleep 0.4; ( $PSQL -d $DB -At -c "begin; $(claims $BED) set local role authenticated; select public.bon_ondertekenen('$B2','Jan','$SIG','$fp'); commit;" > $TMP/w2 2>&1 ) & wait
ok "gelijktijdige bedrijfswissel: tekenen wacht en wordt geweigerd; regel blijft wachten, rekening op het nieuwe bedrijf" $(grep -q "Bedrijf verschilt" $TMP/w2 && [ "$(bonst $B2)" = "pending_approval" ] && [ "$(regel2)" = "pending|$A100" ] && [ "$(sql "select company_id from open_tabs where id='$T4'")" = "$A105" ] && echo 1) "$(cat $TMP/w2 | tr '\n' ' ')"

# 4d. afwijzen en tekenen tegelijk (blokkade uit de review van 17 okt): nooit een vergrendelde bon zonder handtekening.
# Elke bewering: bon, regel en handtekening samen consistent. Gelijktijdig = twee echte transacties naast elkaar.
staat() { sql "select (select status from receipts where id='$BON') || '|' || string_agg(status || ':' || (signature_data is not null), ',' order by created_at) from approvals where receipt_id='$BON'"; }
afwijs_sql="update approvals set status='rejected', metadata='{\"reason\":\"x\"}' where id='$REGEL'"
# 1. de manager wijst af (nog niet vastgelegd) voordat het tekenen de regel vergrendelt: tekenen wacht en weigert daarna
na; fp=$(vinger)
( $PSQL -d $DB -At -c "begin; $(claims $MGR) set local role authenticated; $afwijs_sql; select pg_sleep(1.5); commit;" > $TMP/a1 2>&1 ) &
sleep 0.4; ( $PSQL -d $DB -At -c "begin; $(claims $BED) set local role authenticated; select public.bon_ondertekenen('$BON','Jan','$SIG','$fp'); commit;" > $TMP/a2 2>&1 ) & wait
ok "gelijktijdig 1: afwijzing eerst, tekenen wacht op de regel en weigert (wacht niet); bon blijft wachten, regel afgewezen, geen handtekening" $(grep -q "wacht niet" $TMP/a2 && ! grep -q ERROR $TMP/a1 && [ "$(staat)" = "pending_approval|rejected:false" ] && echo 1) "$(staat) | $(tr '\n' ' ' < $TMP/a2)"
# 2. het tekenen vergrendelt de regel eerst; de manager wijst tegelijk af: afwijzing wacht en wordt daarna geweigerd
na; fp=$(vinger)
( $PSQL -d $DB -At -c "begin; $(claims $BED) set local role authenticated; select public.bon_ondertekenen('$BON','Jan','$SIG','$fp'); select pg_sleep(1.5); commit;" > $TMP/a3 2>&1 ) &
sleep 0.4; ( $PSQL -d $DB -At -c "begin; $(claims $MGR) set local role authenticated; $afwijs_sql; commit;" > $TMP/a4 2>&1 ) & wait
ok "gelijktijdig 2: tekenen eerst, afwijzing wacht en wordt geweigerd; bon locked, regel approved met handtekening" $(grep -q "^locked" $TMP/a3 && grep -q "afgehandelde goedkeuring" $TMP/a4 && [ "$(staat)" = "locked|approved:true" ] && echo 1) "$(staat) | $(tr '\n' ' ' < $TMP/a4)"
# 3. de regel is al afgewezen (vastgelegd) als er getekend wordt
na; fp=$(vinger); als $MGR "$afwijs_sql" >/dev/null; r=$(teken $BON $BED "Jan" "$fp")
ok "al afgewezen: tekenen geweigerd; bon blijft wachten, regel afgewezen, geen handtekening" $(echo "$r" | grep -q "wacht niet" && [ "$(staat)" = "pending_approval|rejected:false" ] && echo 1) "$(staat) $r"
# 4. aantal bijgewerkte regels wijkt af (testtrigger slaat de regel over): alles terug, ook de bon
na; sql "create function public.test_overslaan() returns trigger language plpgsql as \$f\$ begin if new.approved_by = 'Overslaan' then return null; end if; return new; end \$f\$;
     create trigger zz_test_overslaan before update on public.approvals for each row execute function public.test_overslaan()" >/dev/null
r=$(teken $BON $BED "Overslaan"); ok "regel niet bijgewerkt (0 van 1): geweigerd (Regel gewijzigd), bon blijft wachten, regel pending, geen handtekening" $(echo "$r" | grep -q "Regel gewijzigd" && [ "$(staat)" = "pending_approval|pending:false" ] && echo 1) "$(staat) $r"
sql "drop trigger zz_test_overslaan on public.approvals; drop function public.test_overslaan()" >/dev/null
r=$(teken); ok "zonder testtrigger: normale ondertekening lukt weer (locked, approved met handtekening)" $([ "$r" = "locked" ] && [ "$(staat)" = "locked|approved:true" ] && echo 1) "$(staat) $r"
# 5. herstelroute beheerder (gedocumenteerd): afwijzen kan in de app niet; de beheerder kan dat in de SQL-editor met de rol
#    service_role (dezelfde smalle uitzondering als de publieke link: bon -> linked, regel -> rejected). Daarna opnieuw indienen en tekenen.
na; r=$(rol service_role "update receipts set status='linked' where id='$BON'; update approvals set status='rejected', metadata='{\"reason\":\"beheerder\"}' where id='$REGEL' returning id")
ok "beheerder (service_role) wijst een handtekeningbon af: bon linked, regel rejected, geen handtekening" $(echo "$r" | grep -q "^[0-9a-f]\{8\}-" && [ "$(staat)" = "linked|rejected:false" ] && echo 1) "$(staat) $r"
r1=$(als $BED "select public.bon_indienen('$BON', 'x')"); r=$(teken)
ok "daarna opnieuw indienen (nieuwe regel) en tekenen: lukt" $([ "$r1" = "signature" ] && [ "$r" = "locked" ] && [ "$(staat)" = "locked|rejected:false,approved:true" ] && echo 1) "$(staat) $r1 $r"
na; r=$($PSQL -d $DB -At -c "update receipts set status='linked' where id='$BON'" 2>&1 | grep -m1 ERROR)
ok "als postgres zonder rol (SQL-editor zonder service_role): afwijzen geweigerd door de bonwacht" $(echo "$r" | grep -q "Geen recht om een bon af te wijzen" && echo 1) "$r"

# 5. wie mag tekenen
na
ok "andere restaurant (bediening B): bon niet gevonden" $(teken $BON $BEDB "Jan" "$(vinger)" | grep -q "Bon niet gevonden" && [ "$(bonst)" = "pending_approval" ] && echo 1)
ok "inactieve medewerker: geen recht" $(teken $BON $UIT "Jan" "$(vinger)" | grep -q "Geen recht" && echo 1)
ok "keuken (geen MANAGE_RECEIPTS): geen recht" $(teken $BON $KEU "Jan" "$(vinger)" | grep -q "Geen recht" && echo 1)
ok "administratie (MANAGE_RECEIPTS) mag laten tekenen" $([ "$(teken $BON $ADM)" = "locked" ] && echo 1)
na
ok "anon: geen recht op de functie" $(rol anon "select public.bon_ondertekenen('$BON','Jan','$SIG','x')" | grep -q "permission denied" && echo 1)
ok "service_role: geen recht op de functie" $(rol service_role "select public.bon_ondertekenen('$BON','Jan','$SIG','x')" | grep -q "permission denied" && echo 1)
ok "anon: geen recht op bon_vingerafdruk" $(rol anon "select public.bon_vingerafdruk('$BON')" | grep -q "permission denied" && echo 1)
ok "vingerafdruk van een bon van een ander restaurant: leeg (RLS)" $([ "$(vinger $BON $BEDB)" = "" ] && echo 1)
sql "delete from restaurant_features where restaurant_id='$RA' and feature='signature'" >/dev/null
ok "module Handtekening uit: geweigerd" $(teken | grep -q "Module staat uit" && [ "$(bonst)" = "pending_approval" ] && echo 1)
opzet; sql "insert into restaurant_features values ('$RA','approval',false,now())" >/dev/null
ok "module Goedkeuring uit: geweigerd" $(teken | grep -q "Module staat uit" && echo 1)
na; sql "set session_replication_role = replica; update approvals set method='qr' where id='$REGEL'" >/dev/null
ok "bon met QR-regel: geweigerd (wacht niet op handtekening)" $(teken | grep -q "wacht niet" && [ "$(bonst)" = "pending_approval" ] && echo 1)
na; sql "set session_replication_role = replica; insert into approvals (receipt_id, company_id, method, status) values ('$BON','a0000000-0000-0000-0000-000000000105','signature','pending')" >/dev/null
ok "tegenstrijdige wachtende regels: geweigerd" $(teken | grep -q "wacht niet" && echo 1)
na; ok "bon die niet wacht (linked): geweigerd" $(teken $BON0 | grep -q "wacht niet" && echo 1)

# 6. directe wegen en misbruik van de markering
na
ok "bediening zet de bon zelf op locked: geweigerd" $(als $BED "update receipts set status='locked' where id='$BON' returning id" | grep -q "Geen recht" && [ "$(bonst)" = "pending_approval" ] && echo 1)
ok "manager keurt een handtekeningbon direct goed: geweigerd" $(als $MGR "update receipts set status='locked' where id='$BON' returning id" | grep -q "vraagt een handtekening" && [ "$(bonst)" = "pending_approval" ] && echo 1)
ok "manager zet een handtekeningregel direct op approved: geweigerd" $(als $MGR "update approvals set status='approved', approved_by='x' where id='$REGEL' returning id" | grep -q "handtekening kan alleen" && echo 1)
ok "manager zet de markering zelf en keurt goed: geweigerd (geen postgres)" $(als $MGR "select set_config('polder.ondertekening','$BON',true); update receipts set status='locked' where id='$BON' returning id" | grep -q "vraagt een handtekening" && [ "$(bonst)" = "pending_approval" ] && echo 1)
ok "manager zet de markering zelf en keurt de regel goed met handtekening: geweigerd" $(als $MGR "select set_config('polder.ondertekening','$BON',true); update approvals set status='approved', approved_by='x', signature_data='$SIG' where id='$REGEL' returning id" | grep -q "handtekening kan alleen" && [ "$(regel)" = "pending||false" ] && echo 1)
ok "manager keurt een QR-regel goed en zet er een handtekening bij: geweigerd" $(sql "set session_replication_role = replica; insert into approvals (id, receipt_id, company_id, method, status) values ('a0000000-0000-0000-0000-000000000498','$BON0','$A100','qr','pending')" >/dev/null; als $MGR "update approvals set status='approved', approved_by='x', signature_data='$SIG' where id='a0000000-0000-0000-0000-000000000498' returning id" | grep -q "handtekening kan alleen" && echo 1)
ok "manager wijst een handtekeningbon af: mag (bon linked, regel rejected)" $(als $MGR "update receipts set status='linked' where id='$BON'; update approvals set status='rejected', metadata='{\"reason\":\"x\"}' where id='$REGEL' returning id" | grep -q "^[0-9a-f]\{8\}-" && [ "$(bonst)" = "linked" ] && echo 1)
# een QR-bon (geen handtekening) en een andere SECURITY DEFINER-functie van postgres
na; QR=a0000000-0000-0000-0000-000000000303
sql "set session_replication_role = replica; update receipts set status='pending_approval' where id='$QR'; insert into approvals (id, receipt_id, company_id, method, status, verification_code) values ('a0000000-0000-0000-0000-000000000499','$QR','$A100','qr','pending','tok')" >/dev/null
sql "create function public.ander(p uuid) returns int language plpgsql security definer set search_path = public, pg_temp as \$f\$ begin update receipts set status = 'locked' where id = p; return 1; end \$f\$;
     create function public.ander_regel(p uuid) returns int language plpgsql security definer set search_path = public, pg_temp as \$f\$ begin update approvals set status = 'approved', signature_data = null where receipt_id = p; return 1; end \$f\$;
     grant execute on function public.ander(uuid), public.ander_regel(uuid) to authenticated" >/dev/null
ok "bediening zet de markering zelf op een QR-bon en keurt goed: geweigerd" $(als $BED "select set_config('polder.ondertekening','$QR',true); update receipts set status='locked' where id='$QR' returning id" | grep -q "Geen recht" && [ "$(bonst $QR)" = "pending_approval" ] && echo 1)
ok "andere DEFINER-functie (bediening, QR-bon): bon geweigerd" $(als $BED "select public.ander('$QR')" | grep -q "Geen recht" && [ "$(bonst $QR)" = "pending_approval" ] && echo 1)
ok "andere DEFINER-functie (bediening, QR-regel): regel geweigerd" $(als $BED "select public.ander_regel('$QR')" | grep -q "Geen recht om een goedkeuring" && echo 1)
ok "andere DEFINER-functie (manager, handtekeningbon): geweigerd" $(als $MGR "select public.ander('$BON')" | grep -q "vraagt een handtekening" && [ "$(bonst)" = "pending_approval" ] && echo 1)
ok "andere DEFINER-functie (bediening, handtekeningbon): geweigerd" $(als $BED "select public.ander('$BON')" | grep -q "Geen recht" && echo 1)
r=$(pg $BED "select public.bon_ondertekenen('$QR','Jan','$SIG',public.bon_vingerafdruk('$QR'))"); ok "bon_ondertekenen op een QR-bon: geweigerd" $(echo "$r" | grep -q "wacht niet" && echo 1) "$r"
# markering na een fout: de functie faalt na de updates -> alles terug, markering leeg, daarna niets meer mogelijk
sql "create function public.test_fout() returns trigger language plpgsql as \$f\$ begin if new.approved_by = 'Fout Test' then raise exception 'testfout'; end if; return new; end \$f\$;
     create trigger zz_test_fout before update on public.approvals for each row execute function public.test_fout()" >/dev/null
r=$($PSQL -d $DB -c "begin; $(claims $BED) do \$d\$ begin begin perform public.bon_ondertekenen('$BON','Fout Test','$SIG',public.bon_vingerafdruk('$BON')); exception when others then raise notice 'fout: %', sqlerrm; end;
  raise notice 'markering=[%]', coalesce(current_setting('polder.ondertekening', true), ''); update receipts set status = 'locked' where id = '$BON'; end \$d\$; commit;" 2>&1)
ok "fout na de updates: alles terug, markering leeg, daarna zelf goedkeuren geweigerd" $(echo "$r" | grep -q "markering=\[\]" && echo "$r" | grep -q "Geen recht om een bon goed te keuren" && [ "$(bonst)" = "pending_approval" ] && [ "$(regel)" = "pending||false" ] && echo 1) "$r"
r=$($PSQL -d $DB -c "begin; $(claims $BED) do \$d\$ begin begin perform public.bon_ondertekenen('$BON','Fout Test','$SIG',public.bon_vingerafdruk('$BON')); exception when others then null; end; raise notice 'markering=[%]', coalesce(current_setting('polder.ondertekening', true), ''); end \$d\$; commit;" 2>&1)
ok "markering na een fout in een subtransactie: leeg" $(echo "$r" | grep -q "markering=\[\]" && echo 1) "$r"
sql "drop trigger zz_test_fout on public.approvals; drop function public.test_fout()" >/dev/null

# 7. gelijktijdig tekenen: precies een lukt
na; fp=$(vinger)
( $PSQL -d $DB -At -c "begin; $(claims $BED) set local role authenticated; select public.bon_ondertekenen('$BON','Klant Een','$SIG','$fp'); select pg_sleep(1); commit;" > $TMP/p1 2>&1 ) &
sleep 0.3; ( $PSQL -d $DB -At -c "begin; $(claims $BED) set local role authenticated; select public.bon_ondertekenen('$BON','Klant Twee','$SIG','$fp'); commit;" > $TMP/p2 2>&1 ) & wait
ok "gelijktijdig: de eerste lukt, de tweede wacht en wordt geweigerd; een regel met de eerste naam" $(grep -q "^locked" $TMP/p1 && grep -q "wacht niet\|gewijzigd" $TMP/p2 && [ "$(regel)" = "approved|Klant Een|true" ] && [ "$(sql "select count(*) from approvals where receipt_id='$BON' and status='approved'")" = "1" ] && echo 1) "$(cat $TMP/p1 $TMP/p2 | tr '\n' ' ')"

# 8. bestaande methoden blijven werken
na; sql "set session_replication_role = replica; update approvals set method='qr', verification_code='tok301' where id='$REGEL'" >/dev/null
ok "QR via de publieke link (service_role): bon locked, regel approved" $(rol service_role "update receipts set status='locked' where id='$BON'; update approvals set status='approved', approved_by='link' where id='$REGEL' returning id" | grep -q "^[0-9a-f]\{8\}-" && [ "$(bonst)" = "locked" ] && echo 1)
na; sql "set session_replication_role = replica; update approvals set method='restaurant_confirms', verification_code=null where id='$REGEL'" >/dev/null
ok "restaurant bevestigt (manager): bon locked" $(als $MGR "update receipts set status='locked' where id='$BON'; update approvals set status='approved', approved_by='m' where id='$REGEL' returning id" | grep -q "^[0-9a-f]\{8\}-" && [ "$(bonst)" = "locked" ] && echo 1)
na; sql "set session_replication_role = replica; update approvals set method='pin', verification_code=null where id='$REGEL'" >/dev/null
rid=$(rol service_role "select r->>'id' from public.pin_poging_start('$A100','$BON') r"); rol service_role "select public.pin_poging_afronden('$rid', true)" >/dev/null
ok "PIN (reservering + manager): bon approved" $(als $MGR "update receipts set status='approved' where id='$BON' returning id" | grep -q "^[0-9a-f]\{8\}-" && [ "$(bonst)" = "approved" ] && echo 1)
ok "PIN zonder reservering blijft geweigerd" $(na; sql "set session_replication_role = replica; update approvals set method='pin' where id='$REGEL'" >/dev/null; als $MGR "update receipts set status='approved' where id='$BON' returning id" | grep -q "PIN-goedkeuring ontbreekt" && echo 1)

# 9. bewust kapotte versies: elke mutatie moet door een test hierboven betrapt worden
mut() { # $1 naam, $2 functie, $3 oud, $4 nieuw, $5 test (shell-functie die 1 geeft als de echte versie goed gedrag toont)
  na; [ "$($5)" = "1" ] || { ok "mutatie $1: test faalt al op de echte versie" 0; return; }
  na; [ -n "${6:-}" ] && $6; muteer "$2" "$3" "$4"; local t; t=$($5)
  ok "mutatie $1: betrapt" $([ "$t" != "1" ] && echo 1) "test slaagde nog"; }
prep_qr() { sql "set session_replication_role = replica; update receipts set status='pending_approval' where id='$QR'; insert into approvals (id, receipt_id, company_id, method, status, verification_code) values ('a0000000-0000-0000-0000-000000000499','$QR','$A100','qr','pending','tok')" >/dev/null
  sql "create function public.ander(p uuid) returns int language plpgsql security definer set search_path = public, pg_temp as \$f\$ begin update receipts set status = 'locked' where id = p; return 1; end \$f\$;
       create function public.ander_regel(p uuid) returns int language plpgsql security definer set search_path = public, pg_temp as \$f\$ begin update approvals set status = 'approved' where receipt_id = p; return 1; end \$f\$;
       grant execute on function public.ander(uuid), public.ander_regel(uuid) to authenticated" >/dev/null; }
t_ander()      { prep_qr; als $BED "select public.ander('$QR')" | grep -q "Geen recht" && [ "$(bonst $QR)" = "pending_approval" ] && echo 1; }
t_ander_regel(){ prep_qr; als $BED "select public.ander_regel('$QR')" | grep -q "Geen recht" && echo 1; }
t_zelf_qr()    { prep_qr; als $BED "select set_config('polder.ondertekening','$QR',true); update receipts set status='locked' where id='$QR' returning id" | grep -q "Geen recht" && echo 1; }
t_mgr_mk()     { als $MGR "select set_config('polder.ondertekening','$BON',true); update receipts set status='locked' where id='$BON' returning id" | grep -q "vraagt een handtekening" && echo 1; }
t_mgr_direct() { als $MGR "update receipts set status='locked' where id='$BON' returning id" | grep -q "vraagt een handtekening" && echo 1; }
t_leeg()       { r=$(pg $BED "select public.bon_ondertekenen('$BON','Jan Klant','$SIG',public.bon_vingerafdruk('$BON')); select coalesce(nullif(current_setting('polder.ondertekening', true), ''), '<leeg>')"); [ "$r" = "<leeg>" ] && [ "$(bonst)" = "locked" ] && echo 1; }
t_tenant()     { teken $BON $BEDB "Jan" "$(vinger)" | grep -q "Bon niet gevonden" && [ "$(bonst)" = "pending_approval" ] && echo 1; }
t_methode()    { sql "set session_replication_role = replica; update approvals set method='qr' where id='$REGEL'" >/dev/null; teken | grep -q "wacht niet" && echo 1; }
t_vinger()     { teken $BON $BED "Jan" "00000000000000000000000000000000" | grep -q "gewijzigd" && echo 1; }
t_anon()       { rol anon "select public.bon_ondertekenen('$BON','Jan','$SIG','x')" | grep -q "permission denied" && echo 1; }
t_check()      { [ "$(check | cut -d'|' -f3)" = "t" ] && echo 1; }
t_module()     { sql "delete from restaurant_features where feature='signature'" >/dev/null; teken | grep -q "Module staat uit" && echo 1; }
t_rol()        { teken $BON $KEU "Jan" "$(vinger)" | grep -q "Geen recht" && echo 1; }
G="public.receipts_guard()"; R="public.approvals_guard()"; T="public.teken_wacht()"; O="public.bon_ondertekenen(uuid,text,text,text)"
mut "bonwacht zonder coalesce (NULL-fout)" $G "coalesce(current_setting('polder.ondertekening', true), '') = new.id::text" "current_setting('polder.ondertekening', true) = new.id::text" t_ander
mut "regelwacht zonder coalesce (NULL-fout)" $R "coalesce(current_setting('polder.ondertekening', true), '') = new.receipt_id::text" "current_setting('polder.ondertekening', true) = new.receipt_id::text" t_ander_regel
mut "bonwacht zonder controle op postgres" $G "and current_user = 'postgres'
              and coalesce" "and coalesce" t_zelf_qr
mut "teken_wacht zonder controle op postgres (bon)" $T "mk := current_user = 'postgres' and coalesce(current_setting('polder.ondertekening', true), '') = new.id::text" "mk := coalesce(current_setting('polder.ondertekening', true), '') = new.id::text" t_mgr_mk
mut "teken_wacht zonder bon-eis" $T "if eis <> mk then" "if mk and not eis then" t_mgr_direct
mut "markering niet leeggemaakt" $O "perform set_config('polder.ondertekening', '', true);" "" t_leeg
mut "geen restaurantcontrole" $O "where id = p_bon and restaurant_id = r for update" "where id = p_bon for update" t_tenant
mut "geen vingerafdrukcontrole" $O "if p_vingerafdruk is distinct from bon_vingerafdruk(p_bon) then" "if false then" t_vinger
mut "geen modulecontrole" $O "if not (feature_aan(r, 'approval') and feature_aan(r, 'signature')) then" "if false then" t_module
mut "geen rolcontrole" $O "if r is null or not has_perm('MANAGE_RECEIPTS') then" "if r is null then" t_rol
# PNG en bedrijf (herstelronde)
PNG="public.png_geldig(text)"; VA="public.bon_vingerafdruk(uuid)"
t_png_rommel() { teken $BON $BED "Jan" "" "data:image/png;base64,$(python3 -c "print('A'*200)")" | grep -q "Geen PNG" && echo 1; }
t_png_tekst()  { teken $BON $BED "Jan" "" "$(pngurl 10 10 geen_png)" | grep -q "Geen PNG" && echo 1; }
t_png_iend()   { [ "$(pngsql "$(pngurl 10 10 zonder_iend 400)")" = "f" ] && echo 1; }
t_png_maat()   { [ "$(pngsql "$(pngurl 2049 10)")" = "f" ] && [ "$(pngsql "$(pngurl 10 1025)")" = "f" ] && echo 1; }
t_png_spatie() { [ "$(pngsql "$(pngurl 10 10 spatie)")" = "f" ] && echo 1; }
t_png_groot()  { [ "$(pngsql "$TEGROOT")" = "f" ] && echo 1; }
t_bedrijf()    { opzet_b2; wissel; teken $B2 $BED "Jan" "$(vinger $B2)" | grep -q "Bedrijf verschilt" && [ "$(bonst $B2)" = "pending_approval" ] && echo 1; }
t_vinger_bedrijf() { opzet_b2; a=$(vinger $B2); wissel; [ "$a" != "$(vinger $B2)" ] && echo 1; }
t_slot()       { opzet_b2; local fp; fp=$(vinger $B2)
  ( $PSQL -d $DB -At -c "begin; $(claims $OWN) set local role authenticated; update open_tabs set company_id='$A105' where id='$T4'; select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
  sleep 0.4; $PSQL -d $DB -At -c "begin; $(claims $BED) set local role authenticated; select public.bon_ondertekenen('$B2','Jan','$SIG','$fp'); commit;" > $TMP/w3 2>&1; wait
  grep -q "Bedrijf verschilt" $TMP/w3 && [ "$(bonst $B2)" = "pending_approval" ] && echo 1; }
mut "PNG-controle niet aangeroepen" $O "if not png_geldig(p_handtekening) then" "if false then" t_png_rommel
mut "png_geldig zonder decoderen (alleen voorvoegsel en tekens)" $PNG "return substr(b, 1, 16) = " "return true or substr(b, 1, 16) = " t_png_tekst
mut "png_geldig zonder IEND-controle" $PNG "and substr(b, length(b) - 11) = '\\x0000000049454e44ae426082'::bytea" "" t_png_iend
mut "png_geldig zonder afmetingen" $PNG "between 1 and 2048" "between 1 and 99999" t_png_maat
mut "png_geldig zonder tekencontrole (witruimte)" $PNG "or substr(p, 23) !~ '^[A-Za-z0-9+/]+={0,2}\$'" "" t_png_spatie
mut "png_geldig zonder lengtegrens" $PNG "length(p) not between 100 and 200000" "length(p) < 100" t_png_groot
mut "geen bedrijfscontrole" $O "if not found then raise exception 'Bedrijf verschilt'" "if false then raise exception 'Bedrijf verschilt'" t_bedrijf
mut "vingerafdruk zonder bedrijf van de rekening" $VA "b.status, (select company_id from open_tabs where id = b.open_tab_id)," "b.status," t_vinger_bedrijf
mut "rekening niet vergrendeld (geen for share)" $O "and company_id = c for share;" "and company_id = c;" t_slot
# gelijktijdig afwijzen (review 17 okt)
t_regelslot() { local fp; fp=$(vinger)
  ( $PSQL -d $DB -At -c "begin; $(claims $MGR) set local role authenticated; $afwijs_sql; select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
  sleep 0.4; $PSQL -d $DB -At -c "begin; $(claims $BED) set local role authenticated; select public.bon_ondertekenen('$BON','Jan','$SIG','$fp'); commit;" > $TMP/a5 2>&1; wait
  grep -q "wacht niet" $TMP/a5 && [ "$(staat)" = "pending_approval|rejected:false" ] && echo 1; }
t_telling() { sql "create function public.test_overslaan() returns trigger language plpgsql as \$f\$ begin if new.approved_by = 'Overslaan' then return null; end if; return new; end \$f\$;
     create trigger zz_test_overslaan before update on public.approvals for each row execute function public.test_overslaan()" >/dev/null
  teken $BON $BED "Overslaan" >/dev/null; [ "$(staat)" = "pending_approval|pending:false" ] && echo 1; }
mut "regel niet vergrendeld (geen for update)" $O "perform from approvals where receipt_id = p_bon and status = 'pending' for update;" "" t_regelslot
mut "aantal bijgewerkte regels niet gecontroleerd" $O "if x <> n then raise" "if false then raise" t_telling
na; muteer $O "perform from approvals where receipt_id = p_bon and status = 'pending' for update;" ""; muteer $O "if x <> n then raise" "if false then raise"
ok "mutatie zonder regelslot en zonder telling (de oorspronkelijke fout): betrapt" $([ "$(t_regelslot)" != "1" ] && echo 1) "$(staat)"
ok "  ... en dan ontstaat precies de gemelde fout: bon locked, regel afgewezen, geen handtekening" $([ "$(staat)" = "locked|rejected:false" ] && echo 1) "$(staat)"
na; muteer $O "perform from approvals where receipt_id = p_bon and status = 'pending' for update;" ""; t_regelslot >/dev/null
ok "zonder regelslot vangt de telling het nog op (tweede laag): Regel gewijzigd, staat consistent" $(grep -q "Regel gewijzigd" $TMP/a5 && [ "$(staat)" = "pending_approval|rejected:false" ] && echo 1) "$(staat) $(tr '\n' ' ' < $TMP/a5)"
na; muteer $O "or k <> 1 or m <> 'signature'" "or k <> 1"; sql "set session_replication_role = replica; update approvals set method='qr' where id='$REGEL'" >/dev/null; r=$(teken)
ok "mutatie geen methodecontrole: functie merkt het niet meer, de wacht (tweede laag) weigert, bon blijft wachten" $(echo "$r" | grep -q "vraagt een handtekening" && [ "$(bonst)" = "pending_approval" ] && [ "$(regel)" = "pending||false" ] && echo 1) "$r"
na; [ "$(t_anon)" = "1" ] && ok "mutatie recht voor anon: echte versie weigert" 1; sql "grant execute on function $O to anon" >/dev/null
ok "mutatie recht voor anon: betrapt" $([ "$(t_anon)" != "1" ] && [ "$(check | cut -d'|' -f3)" = "f" ] && echo 1)
na; sql "alter function $O reset search_path" >/dev/null; ok "mutatie zonder search_path: controleblok meldt het (nieuw_ok = f)" $([ "$(check | cut -d'|' -f3)" = "f" ] && echo 1)
na; sql "alter function $T security definer" >/dev/null; ok "mutatie teken_wacht als DEFINER: controleblok meldt het (nieuw_ok = f)" $([ "$(check | cut -d'|' -f3)" = "f" ] && echo 1)

# 10. controleblok functie (prod-teken14c-functie.sql): code van bon_ondertekenen tegen de goedgekeurde versie uit 0047
fcheck() { $PSQL -d $DB -At -F'|' -f $CF 2>&1 | grep -v '^$' | head -1; }
veld() { echo "$1" | cut -d'|' -f$2; }
# toestand van de hele database (functies, rechten, triggers, tabellen, data van bonnen en regels): moet na het blok exact gelijk zijn
toestand() { sql "select md5(concat_ws('|', (select string_agg(oid::text||proname||md5(prosrc)||coalesce(proacl::text,'')||prosecdef||coalesce(proconfig::text,'')||proowner, ',' order by oid) from pg_proc where pronamespace='public'::regnamespace),
  (select string_agg(tgname||tgenabled, ',' order by tgname) from pg_trigger), (select string_agg(relname||coalesce(relacl::text,''), ',' order by relname) from pg_class where relnamespace='public'::regnamespace),
  (select string_agg(to_jsonb(r)::text, ',' order by id) from receipts r), (select string_agg(to_jsonb(a)::text, ',' order by id) from approvals a)))"; }
VERWACHT=$(python3 - <<'E'
import re, hashlib
s = open("migrations/0047_bon_ondertekenen.sql").read(); a = s.index("as $f$") + 6; b = s.index("$f$;", a)
print(hashlib.md5(re.sub(r"\s+", " ", re.sub(r"--[^\n]*", "", s[a:b])).strip().encode()).hexdigest())
E
)
ok "functieblok: verwachte vingerafdruk = berekend uit het bestand 0047 (niet uit een database): $VERWACHT" $(grep -q "'$VERWACHT'::text as verwacht" $CF && echo 1)
ok "functieblok: begint met begin, eindigt met rollback, bevat alleen een leesopdracht" $([ "$(grep -v '^--' $CF | head -1)" = "begin;" ] && [ "$(tail -1 $CF)" = "rollback;" ] \
  && ! grep -v '^--' $CF | grep -qiE '\b(insert|update|delete|create|alter|drop|grant|revoke|truncate|set_config|perform|execute|do)\b' && echo 1)
vers; r=$(fcheck); ok "functieblok op 0042: ONTBREEKT, geen fout, kenmerken f, geen recht" $([ "$(veld "$r" 1)" = "ONTBREEKT" ] && [ "$(veld "$r" 4)" = "f" ] && [ "$(veld "$r" 6)" = "0" ] && ! echo "$r" | grep -q ERROR && echo 1) "$r"
for f in "${MIG[@]:0:5}"; do run $f >/dev/null; done; r=$(fcheck)
ok "functieblok na 0047: GELIJK, kenmerken t, recht alleen postgres" $([ "$(veld "$r" 1)" = "GELIJK" ] && [ "$(veld "$r" 2)" = "$VERWACHT" ] && [ "$(veld "$r" 4)" = "t" ] && [ "$(veld "$r" 5)" = "{postgres=X/postgres}" ] && echo 1) "$r"
run ${MIG[5]} >/dev/null; r=$(fcheck)
ok "functieblok na 0048: GELIJK, kenmerken t, recht postgres + authenticated" $([ "$(veld "$r" 1)" = "GELIJK" ] && [ "$(veld "$r" 4)" = "t" ] && [ "$(veld "$r" 5)" = "{postgres=X/postgres,authenticated=X/postgres}" ] && echo 1) "$r"
O="public.bon_ondertekenen(uuid,text,text,text)"
fcode() { na; muteer $O "$1" "$2"; local t0 t1 r; t0=$(toestand); r=$(fcheck); t1=$(toestand)
  ok "functieblok, $3: $4; database na het blok exact gelijk" $([ "$(veld "$r" 1)" = "$4" ] && [ "$t0" = "$t1" ] && echo 1) "$r"; }
fcode "perform from approvals where receipt_id = p_bon and status = 'pending' for update;" "" "regelslot weggehaald" AFWIJKEND
fcode "if x <> n then raise" "if false then raise" "telling uitgezet" AFWIJKEND
fcode "if not png_geldig(p_handtekening) then" "if false then" "PNG-controle uitgezet" AFWIJKEND
fcode "where id = p_bon and restaurant_id = r for update" "where id = p_bon for update" "restaurantcontrole weggehaald" AFWIJKEND
fcode "'Geen recht'" "'Geen rechten'" "alleen een melding gewijzigd (ook code)" AFWIJKEND
fcode "  perform set_config('polder.ondertekening', '', true);" "  perform   set_config('polder.ondertekening', '', true);   -- extra commentaar" "alleen witruimte en commentaar" GELIJK
fkenmerk() { na; sql "$1" >/dev/null; local t0 t1 r; t0=$(toestand); r=$(fcheck); t1=$(toestand)
  ok "functieblok, $2: kenmerken_ok = f (code GELIJK); database na het blok exact gelijk" $([ "$(veld "$r" 1)" = "GELIJK" ] && [ "$(veld "$r" 4)" = "f" ] && [ "$t0" = "$t1" ] && echo 1) "$r"; }
fkenmerk "alter function $O security invoker" "SECURITY INVOKER in plaats van DEFINER"
fkenmerk "alter function $O reset search_path" "zonder vaste search_path"
fkenmerk "create role hk_ander; alter function $O owner to hk_ander" "andere eigenaar"
$PSQL -d postgres -c "drop database if exists $DB" >/dev/null 2>&1; $PSQL -d postgres -c "drop role if exists hk_ander" >/dev/null 2>&1
na; sql "create function public.bon_ondertekenen(p uuid) returns text language sql as 'select null::text'" >/dev/null; r=$(fcheck)
ok "functieblok: extra versie met dezelfde naam wordt gemeld (aantal_versies 2), de echte blijft GELIJK" $([ "$(veld "$r" 1)" = "GELIJK" ] && [ "$(veld "$r" 6)" = "2" ] && echo 1) "$r"
na; sql "revoke execute on function $O from authenticated; drop function $O" >/dev/null; r=$(fcheck)
ok "functieblok: functie verwijderd -> ONTBREEKT, geen fout" $([ "$(veld "$r" 1)" = "ONTBREEKT" ] && ! echo "$r" | grep -q ERROR && echo 1) "$r"
na; muteer $O "if x <> n then raise" "if false then raise"; r=$($PSQL -d $DB -v ON_ERROR_STOP=1 -At -F'|' -f $CF 2>&1; echo "exit=$?")
ok "functieblok op een afwijkende database: geen fout, eindigt met rollback (exit 0), oordeel AFWIJKEND" $(echo "$r" | grep -q "^AFWIJKEND" && echo "$r" | grep -q "exit=0" && echo 1) "$r"

$PSQL -d postgres -c "drop database if exists $DB" >/dev/null 2>&1
echo "== RESULTAAT: $pass PASS, $fail FAIL"
[ $fail = 0 ]
