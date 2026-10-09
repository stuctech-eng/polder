#!/bin/bash
# Tests voor de preflight van migratie 0023 en van 0023_rollback.sql (plan 7b, versie 5).
# Alleen lokaal/staging, op een database waar 0020-0022 (en eventueel 0023) staan. NOOIT op productie:
# de test overschrijft bewust open_tabs_guard() met afwijkende varianten (en herstelt daarna).
# Gebruik:  bash preflight-0023-tests.sh <pad naar supabase-map> [psql-opties]
#   bv.   PSQL="psql -X -q -p 55432 -h /home/pgtest -d s3" bash preflight-0023-tests.sh /home/pgtest/w/supabase
set -u
SUP="${1:?pad naar de supabase-map}"
PSQL="${PSQL:-psql -X -q -p 55432 -h /home/pgtest -d s3}"
MIG="$SUP/migrations/0023_hardening_plan7b_invoice_block.sql"
RB="$SUP/rollbacks/0023_rollback.sql"
M21="$SUP/migrations/0021_hardening_step7_tabs_receipts.sql"
TMP=$(mktemp -d)
cleanup_role() { $PSQL -q -c "do \$\$ begin if exists (select 1 from pg_roles where rolname='pf_tmp_grantee') then revoke pf_tmp_grantee from anon; revoke all on function public.open_tabs_guard() from pf_tmp_grantee; drop role pf_tmp_grantee; end if; end \$\$;" >/dev/null 2>&1; }
trap 'cleanup_role; rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { if [ "$2" = "ok" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1  -> $3"; fi; }

# --- de functietekst van 0021 (de verwachte uitgangsversie) uit het migratiebestand halen
M22="$SUP/migrations/0022_hardening_step7_approvals_guard.sql"
python3 - "$M21" "$TMP" "$MIG" "$M22" <<'PY'
import sys,re
s=open(sys.argv[1]).read()
i=s.index("create or replace function public.open_tabs_guard()")
j=s.index("create or replace function public.approvals_guard()")
fn=s[i:j].rstrip()+"\n"
open(sys.argv[2]+"/fn0021.sql","w").write(fn)
t=open(sys.argv[4]).read()
i2=t.index("create or replace function public.approvals_guard()"); j2=t.index("end $$;",i2)+len("end $$;")
ag=t[i2:j2]+"\n"
open(sys.argv[2]+"/ag0022.sql","w").write(ag)
open(sys.argv[2]+"/ag_comment.sql","w").write(ag.replace("begin\n","begin\n  -- extra opmerking\n",1))
k=ag.rindex("end $$;")
open(sys.argv[2]+"/ag_stmt.sql","w").write(ag[:k].rstrip()+"\n  perform 1;\nend $$;\n")
open(sys.argv[2]+"/fn_prod.sql","w").write(fn.replace("  -- UPDATE\n","",1))
open(sys.argv[2]+"/fn_prod_stmt.sql","w").write(fn.replace("  -- UPDATE\n","",1).replace("  return new;\nend $$;","  perform 1;\n  return new;\nend $$;"))
import re as _re
_strip=lambda x:"\n".join(_re.sub(r"\s*--.*$","",l) for l in x.split("\n"))
open(sys.argv[2]+"/ag_prod.sql","w").write(_strip(ag))
_k=_strip(ag).rindex("end $$;")
open(sys.argv[2]+"/ag_prod_stmt.sql","w").write(_strip(ag)[:_k].rstrip()+"\n  perform 1;\nend $$;\n")
_m=open(sys.argv[3]).read(); _a=_m.index("create or replace function public.open_tabs_guard()"); _b=_m.index("revoke all on function public.open_tabs_guard()", _a)
_f23=_m[_a:_b].rstrip()+"\n"
open(sys.argv[2]+"/fn23_prod.sql","w").write(_strip(_f23))
_k=_strip(_f23).rindex("end $$;")
open(sys.argv[2]+"/fn23_prod_stmt.sql","w").write(_strip(_f23)[:_k].rstrip()+"\n  perform 1;\nend $$;\n")
open(sys.argv[2]+"/fn_comment.sql","w").write(fn.replace("begin\n  if tg_op = 'DELETE' then","begin\n  -- extra opmerking\n  if tg_op = 'DELETE' then",1))
open(sys.argv[2]+"/fn_stmt.sql","w").write(fn.replace("  return new;\nend $$;","  perform 1;\n  return new;\nend $$;"))
# alleen witruimte: CRLF en extra inspringing (moet dezelfde fingerprint geven)
m=open(sys.argv[3]).read()
a=m.index("create or replace function public.open_tabs_guard()"); b=m.index("revoke all on function public.open_tabs_guard()", a)
f23=m[a:b].rstrip()+"\n"
open(sys.argv[2]+"/fn23_comment.sql","w").write(f23.replace("begin\n  if tg_op = 'DELETE' then","begin\n  -- extra opmerking\n  if tg_op = 'DELETE' then",1))
open(sys.argv[2]+"/fn_ws.sql","w",newline="").write(fn.replace("\n","\r\n").replace("  if ","      if ").replace("\r\n  ","\r\n      "))
PY
RESET="drop trigger if exists open_tabs_guard on public.receipts; drop trigger if exists extra_guard on public.open_tabs; drop trigger if exists open_tabs_guard on public.open_tabs;"
TRIG="create trigger open_tabs_guard before insert or update or delete on public.open_tabs for each row execute function public.open_tabs_guard();"
REVOKE="revoke all on function public.open_tabs_guard() from public, anon, authenticated, service_role;"
sql() { $PSQL -At -v ON_ERROR_STOP=1 -c "$1" 2>&1; }
file() { $PSQL -At -v ON_ERROR_STOP=1 -f "$1" 2>&1; }
to21() { { echo "begin; $RESET"; cat "$TMP/fn0021.sql"; cat "$TMP/ag0022.sql"; echo "drop trigger if exists approvals_guard on public.approvals; create trigger approvals_guard before insert or update or delete on public.approvals for each row execute function public.approvals_guard(); revoke all on function public.approvals_guard() from public, anon, authenticated, service_role; $REVOKE $TRIG commit;"; } > "$TMP/r21.sql"; file "$TMP/r21.sql" >/dev/null; }
to23() { to21; file "$MIG" >/dev/null; }
snap() { $PSQL -At -c "select md5(pg_get_functiondef('public.open_tabs_guard()'::regprocedure)) || '|' || coalesce((select string_agg(pg_get_triggerdef(oid)||tgenabled::text, ';' order by oid) from pg_trigger where tgname='open_tabs_guard' and not tgisinternal),'-') || '|' || coalesce((select proacl::text from pg_proc where oid='public.open_tabs_guard()'::regprocedure),'-') || '|' || (select prosecdef::text||coalesce(proconfig::text,'-') from pg_proc where oid='public.open_tabs_guard()'::regprocedure) || '|' || (select count(*) from public.open_tabs)||'/'||(select count(*) from public.receipts)||'/'||(select count(*) from public.approvals)"; }
fp() { $PSQL -At -c "select md5(btrim(regexp_replace(prosrc, '\s+', ' ', 'g'))) from pg_proc where oid='public.open_tabs_guard()'::regprocedure"; }
FPLIST=$(grep "if v_hash not in .*dc970c3a" "$MIG" | grep -o "[0-9a-f]\{32\}")
H21=$(echo "$FPLIST" | sed -n 1p); H21P=$(echo "$FPLIST" | sed -n 2p); H23=$(echo "$FPLIST" | sed -n 3p); H23P=$(echo "$FPLIST" | sed -n 4p)
AGL=$(grep "if v_hash not in ('" "$MIG" | head -1 | grep -o "[0-9a-f]\{32\}"); AG=$(echo "$AGL" | sed -n 1p); AGP=$(echo "$AGL" | sed -n 2p)

# afbreken-test: toestand opbouwen (arg 2 = sql-opdracht), bestand uitvoeren, verwachten: fout met tekst, niets gewijzigd
expect_abort() {  # naam, setup-sql, bestand, verwachte tekst
  to21_or_23="$5"; if [ "$to21_or_23" = 23 ]; then to23; else to21; fi
  [ -n "$2" ] && $PSQL -q -v ON_ERROR_STOP=1 -c "$2" >/dev/null 2>&1
  before=$(snap); out=$(file "$3"); rc=$?; after=$(snap)
  if [ $rc -ne 0 ] && echo "$out" | grep -q "$4" && [ "$before" = "$after" ]; then check "$1" ok; else check "$1" bad "rc=$rc; gelijk=$([ "$before" = "$after" ] && echo ja || echo NEE); $(echo "$out" | head -2)"; fi
}
expect_run() {   # naam, setup-sql, bestand, verwachte fingerprint na afloop (leeg = ongewijzigd laten)
  to21_or_23="$5"; if [ "$to21_or_23" = 23 ]; then to23; else to21; fi
  [ -n "$2" ] && $PSQL -q -v ON_ERROR_STOP=1 -c "$2" >/dev/null 2>&1
  before=$(snap); out=$(file "$3"); rc=$?; now=$(fp)
  if [ $rc -eq 0 ] && [ "$now" = "$4" ]; then check "$1" ok; else check "$1" bad "rc=$rc; fingerprint=$now (verwacht $4); $(echo "$out" | head -2)"; fi
}

echo "--- fingerprints: 0021 = $H21, 0021 zonder commentaar (productie) = $H21P, 0023 = $H23, 0023 zonder commentaar = $H23P; approvals_guard 0022 = $AG, zonder commentaar (productie) = $AGP"
to21; [ "$(fp)" = "$H21" ] && check "fingerprint van de 0021-functie klopt met de waarde in de migratie" ok || check "fingerprint 0021" bad "$(fp)"
$PSQL -q -v ON_ERROR_STOP=1 -c "begin; $RESET; $(cat "$TMP/fn_prod.sql"); $REVOKE $TRIG commit;" >/dev/null 2>&1
[ "$(fp)" = "$H21P" ] && check "de 0021-tekst zonder alleen de regel '-- UPDATE' heeft de fingerprint van de productievariant" ok || check "fingerprint productievariant" bad "$(fp)"
to23; [ "$(fp)" = "$H23" ] && check "fingerprint na 0023 klopt met de waarde in de migratie" ok || check "fingerprint 0023" bad "$(fp)"

to21; agfp=$($PSQL -At -c "select md5(btrim(regexp_replace(prosrc, '\s+', ' ', 'g'))) from pg_proc where oid='public.approvals_guard()'::regprocedure")
[ "$agfp" = "$AG" ] && check "fingerprint van approvals_guard (0022-tekst uit het repo) klopt met de waarde in de migratie ($AG)" ok || check "fingerprint approvals_guard" bad "$agfp vs $AG"
$PSQL -q -v ON_ERROR_STOP=1 -c "$(cat "$TMP/ag_prod.sql")" >/dev/null 2>&1
agp=$($PSQL -At -c "select md5(btrim(regexp_replace(prosrc, '\s+', ' ', 'g'))) from pg_proc where oid='public.approvals_guard()'::regprocedure")
[ "$agp" = "$AGP" ] && check "approvals_guard 0022 zonder --commentaren heeft de fingerprint van de productievariant ($AGP)" ok || check "fingerprint approvals_guard zonder commentaar" bad "$agp vs $AGP"
$PSQL -q -v ON_ERROR_STOP=1 -c "$(cat "$TMP/fn23_prod.sql")" >/dev/null 2>&1
f23p=$(fp); [ "$f23p" = "$H23P" ] && check "0023-functie zonder --commentaren heeft de fingerprint $H23P" ok || check "fingerprint 0023 zonder commentaar" bad "$f23p"
echo "--- MIGRATIE 0023: verwachte uitgangsversie mag doorgaan"
expect_run "M1 uitgangsversie 0021: migratie gaat door, functie wordt de 0023-versie" "" "$MIG" "$H23" 21
expect_run "M2 herhaling (al 0023): migratie gaat door, functie blijft de 0023-versie" "" "$MIG" "$H23" 23
expect_run "M3 alleen witruimte/CRLF anders dan 0021: dezelfde fingerprint, migratie gaat door" "begin; $RESET; $(cat "$TMP/fn_ws.sql"); $REVOKE $TRIG commit;" "$MIG" "$H23" 21

echo "--- MIGRATIE 0023: afwijkende uitgangssituatie breekt af, niets gewijzigd"
expect_abort "M4 functie met extra opmerking" "begin; $(cat "$TMP/fn_comment.sql"); $REVOKE commit;" "$MIG" "Preflight 0023: open_tabs_guard() heeft niet de verwachte inhoud" 21
expect_abort "M5 functie met extra opdracht" "begin; $(cat "$TMP/fn_stmt.sql"); $REVOKE commit;" "$MIG" "Preflight 0023: open_tabs_guard() heeft niet de verwachte inhoud" 21
expect_abort "M6 functie is SECURITY DEFINER geworden" "alter function public.open_tabs_guard() security definer;" "$MIG" "afwijkende eigenschappen" 21
expect_abort "M7 andere search_path" "alter function public.open_tabs_guard() set search_path = public;" "$MIG" "afwijkende eigenschappen" 21
expect_abort "M8 functie uitvoerbaar voor authenticated" "grant execute on function public.open_tabs_guard() to authenticated;" "$MIG" "afwijkende uitvoerrechten" 21
expect_abort "M9 functie uitvoerbaar voor iedereen (public)" "grant execute on function public.open_tabs_guard() to public;" "$MIG" "afwijkende uitvoerrechten" 21
expect_abort "M10 trigger uitgeschakeld" "alter table public.open_tabs disable trigger open_tabs_guard;" "$MIG" "staat niet aan of heeft een afwijkende definitie" 21
expect_abort "M11 trigger alleen voor UPDATE" "drop trigger open_tabs_guard on public.open_tabs; create trigger open_tabs_guard before update on public.open_tabs for each row execute function public.open_tabs_guard();" "$MIG" "afwijkende definitie" 21
expect_abort "M12 tweede trigger met dezelfde naam op een andere tabel" "create trigger open_tabs_guard before insert on public.receipts for each row execute function public.open_tabs_guard();" "$MIG" "precies één trigger" 21
expect_abort "M13 trigger ontbreekt" "drop trigger open_tabs_guard on public.open_tabs;" "$MIG" "precies één trigger" 21
expect_abort "M14 0023-versie met extra opmerking: migratie breekt af (geen stilzwijgend overschrijven)" "begin; $(cat "$TMP/fn23_comment.sql"); $REVOKE commit;" "$MIG" "Preflight 0023: open_tabs_guard() heeft niet de verwachte inhoud" 23
expect_abort "M15 functie uitvoerbaar voor anon" "grant execute on function public.open_tabs_guard() to anon;" "$MIG" "afwijkende uitvoerrechten" 21
expect_abort "M16 functie uitvoerbaar voor service_role" "grant execute on function public.open_tabs_guard() to service_role;" "$MIG" "afwijkende uitvoerrechten" 21
expect_abort "M17 ACL leeg (proacl NULL = standaard-ACL, PUBLIC heeft EXECUTE)" "update pg_proc set proacl = null where oid = 'public.open_tabs_guard()'::regprocedure;" "$MIG" "afwijkende uitvoerrechten" 21
expect_abort "M18 anon erft EXECUTE via lidmaatschap van een andere rol" "create role pf_tmp_grantee nologin; grant execute on function public.open_tabs_guard() to pf_tmp_grantee; grant pf_tmp_grantee to anon;" "$MIG" "afwijkende uitvoerrechten" 21
cleanup_role
expect_abort "M19 tijdelijke niet-standaardrol krijgt direct EXECUTE" "create role pf_tmp_grantee nologin; grant execute on function public.open_tabs_guard() to pf_tmp_grantee;" "$MIG" "afwijkende uitvoerrechten" 21
cleanup_role
expect_run "M20 productievariant (0021 zonder '-- UPDATE'-regel): migratie gaat door, functie wordt de 0023-versie" "begin; $RESET; $(cat "$TMP/fn_prod.sql"); $REVOKE $TRIG commit;" "$MIG" "$H23" 21
expect_abort "M21 productievariant met een inhoudelijke wijziging (extra opdracht): migratie breekt af" "begin; $RESET; $(cat "$TMP/fn_prod_stmt.sql"); $REVOKE $TRIG commit;" "$MIG" "Preflight 0023: open_tabs_guard() heeft niet de verwachte inhoud" 21
expect_abort "M22 approvals_guard met extra opmerking: niet exact de versie van 0022" "begin; $(cat "$TMP/ag_comment.sql"); commit;" "$MIG" "approvals_guard() is niet exact de versie van migratie 0022" 21
expect_abort "M23 approvals_guard met extra opdracht (0022-tekstfragment nog aanwezig): migratie breekt af" "begin; $(cat "$TMP/ag_stmt.sql"); commit;" "$MIG" "approvals_guard() is niet exact de versie van migratie 0022" 21
expect_abort "M24 approvals_guard is SECURITY DEFINER" "alter function public.approvals_guard() security definer;" "$MIG" "approvals_guard() heeft afwijkende eigenschappen" 21
expect_abort "M25 approvals_guard uitvoerbaar voor anon" "grant execute on function public.approvals_guard() to anon;" "$MIG" "approvals_guard() heeft afwijkende uitvoerrechten" 21
expect_abort "M26 approvals_guard ontbreekt" "drop trigger approvals_guard on public.approvals; drop function public.approvals_guard();" "$MIG" "approvals_guard() ontbreekt" 21
expect_abort "M27 trigger open_tabs_guard roept een andere functie aan (receipts_guard)" "drop trigger open_tabs_guard on public.open_tabs; create trigger open_tabs_guard before insert or update or delete on public.open_tabs for each row execute function public.receipts_guard();" "$MIG" "afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde)" 21
expect_abort "M28 trigger open_tabs_guard staat op een andere tabel (receipts) i.p.v. open_tabs" "drop trigger open_tabs_guard on public.open_tabs; create trigger open_tabs_guard before insert or update or delete on public.receipts for each row execute function public.open_tabs_guard();" "$MIG" "afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde)" 21
expect_abort "M29 trigger met kolomlijst (UPDATE OF status)" "drop trigger open_tabs_guard on public.open_tabs; create trigger open_tabs_guard before insert or update of status or delete on public.open_tabs for each row execute function public.open_tabs_guard();" "$MIG" "afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde)" 21
expect_abort "M30 trigger met WHEN-voorwaarde" "drop trigger open_tabs_guard on public.open_tabs; create trigger open_tabs_guard before update on public.open_tabs for each row when (old.status is distinct from new.status) execute function public.open_tabs_guard();" "$MIG" "afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde)" 21
expect_abort "M31 trigger is AFTER i.p.v. BEFORE" "drop trigger open_tabs_guard on public.open_tabs; create trigger open_tabs_guard after insert or update or delete on public.open_tabs for each row execute function public.open_tabs_guard();" "$MIG" "afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde)" 21
expect_abort "M32 tweede trigger (andere naam) roept dezelfde functie aan" "create trigger extra_guard before insert on public.open_tabs for each row execute function public.open_tabs_guard();" "$MIG" "afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde)" 21
expect_run "M33 approvals_guard = productievariant (0022 zonder commentaar): migratie gaat door" "begin; $(cat "$TMP/ag_prod.sql"); commit;" "$MIG" "$H23" 21
expect_abort "M34 approvals_guard = productievariant met extra opdracht: migratie breekt af" "begin; $(cat "$TMP/ag_prod_stmt.sql"); commit;" "$MIG" "approvals_guard() is niet exact de versie van migratie 0022" 21
expect_run "M35 herhaling met de commentaarloze 0023-versie: migratie gaat door" "begin; $(cat "$TMP/fn23_prod.sql"); commit;" "$MIG" "$H23" 23
expect_abort "M36 commentaarloze 0023-versie met extra opdracht: migratie breekt af" "begin; $(cat "$TMP/fn23_prod_stmt.sql"); commit;" "$MIG" "Preflight 0023: open_tabs_guard() heeft niet de verwachte inhoud" 23
$PSQL -q -c "drop trigger if exists extra_guard on public.open_tabs;" >/dev/null 2>&1

echo "--- ROLLBACK 0023"
expect_run "R1 huidige functie = versie 0023: rollback gaat door, functie wordt de 0021-versie" "" "$RB" "$H21" 23
expect_abort "R2 al teruggedraaid (functie = 0021-versie): rollback breekt af" "" "$RB" "Preflight rollback 0023: open_tabs_guard() heeft niet de verwachte inhoud" 21
expect_abort "R3 0023-versie met extra opmerking: rollback breekt af" "begin; $(cat "$TMP/fn23_comment.sql"); $REVOKE commit;" "$RB" "niet de verwachte inhoud" 23
expect_abort "R4 trigger uitgeschakeld: rollback breekt af" "alter table public.open_tabs disable trigger open_tabs_guard;" "$RB" "staat niet aan of heeft een afwijkende definitie" 23
expect_abort "R5 functie uitvoerbaar voor service_role: rollback breekt af" "grant execute on function public.open_tabs_guard() to service_role;" "$RB" "afwijkende uitvoerrechten" 23
expect_abort "R6 functie SECURITY DEFINER: rollback breekt af" "alter function public.open_tabs_guard() security definer;" "$RB" "afwijkende eigenschappen" 23
expect_abort "R7 functie uitvoerbaar voor iedereen (public): rollback breekt af" "grant execute on function public.open_tabs_guard() to public;" "$RB" "afwijkende uitvoerrechten" 23
expect_abort "R8 functie uitvoerbaar voor anon: rollback breekt af" "grant execute on function public.open_tabs_guard() to anon;" "$RB" "afwijkende uitvoerrechten" 23
expect_abort "R9 functie uitvoerbaar voor authenticated: rollback breekt af" "grant execute on function public.open_tabs_guard() to authenticated;" "$RB" "afwijkende uitvoerrechten" 23
expect_abort "R10 ACL leeg (proacl NULL): rollback breekt af" "update pg_proc set proacl = null where oid = 'public.open_tabs_guard()'::regprocedure;" "$RB" "afwijkende uitvoerrechten" 23
expect_abort "R11 tijdelijke niet-standaardrol krijgt direct EXECUTE: rollback breekt af" "create role pf_tmp_grantee nologin; grant execute on function public.open_tabs_guard() to pf_tmp_grantee;" "$RB" "afwijkende uitvoerrechten" 23
cleanup_role
expect_abort "R13 trigger roept een andere functie aan: rollback breekt af" "drop trigger open_tabs_guard on public.open_tabs; create trigger open_tabs_guard before insert or update or delete on public.open_tabs for each row execute function public.receipts_guard();" "$RB" "afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde)" 23
expect_abort "R14 trigger op andere tabel: rollback breekt af" "drop trigger open_tabs_guard on public.open_tabs; create trigger open_tabs_guard before insert or update or delete on public.receipts for each row execute function public.open_tabs_guard();" "$RB" "afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde)" 23
expect_abort "R15 trigger met kolomlijst: rollback breekt af" "drop trigger open_tabs_guard on public.open_tabs; create trigger open_tabs_guard before insert or update of status or delete on public.open_tabs for each row execute function public.open_tabs_guard();" "$RB" "afwijkende definitie (tabel, functie, gebeurtenissen of voorwaarde)" 23
expect_run "R16 rollback vanaf de commentaarloze 0023-versie: gaat door, functie wordt de repo-versie van 0021" "begin; $(cat "$TMP/fn23_prod.sql"); commit;" "$RB" "$H21" 23
expect_abort "R17 commentaarloze 0023-versie met extra opdracht: rollback breekt af" "begin; $(cat "$TMP/fn23_prod_stmt.sql"); commit;" "$RB" "niet de verwachte inhoud" 23
# R12: migratie vanuit de productievariant, daarna rollback: de goedgekeurde 0021-functie (mét commentaarregel) komt terug
$PSQL -q -v ON_ERROR_STOP=1 -c "begin; $RESET; $(cat "$TMP/fn_prod.sql"); $REVOKE $TRIG commit;" >/dev/null 2>&1
file "$MIG" >/dev/null; mid=$(fp); file "$RB" >/dev/null; rc=$?; end=$(fp)
if [ "$mid" = "$H23" ] && [ $rc -eq 0 ] && [ "$end" = "$H21" ]; then check "R12 migratie vanuit de productievariant en daarna rollback: functie wordt de repo-versie van 0021" ok; else check "R12" bad "mid=$mid rc=$rc end=$end"; fi

to23   # standaardtoestand terugzetten: 0023 toegepast
echo; echo "$pass PASS, $fail FAIL"; [ $fail -eq 0 ]
