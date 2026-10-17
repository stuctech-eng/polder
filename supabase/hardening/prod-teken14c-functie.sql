-- POLDER controle 14c: functie bon_ondertekenen, ALLEEN LEZEN. Draaien na 0047 en na 0048 (naast prod-teken14c-checks.sql).
-- oordeel: GELIJK = code is exact de goedgekeurde versie uit migratie 0047; AFWIJKEND = andere code; ONTBREEKT = functie bestaat niet.
-- code_md5: md5 van de functietekst zonder commentaar, witruimte samengevoegd. De verwachte waarde is berekend uit het bestand
-- supabase/migrations/0047_bon_ondertekenen.sql (niet uit een database). kenmerken_ok: DEFINER, eigenaar postgres, vaste search_path,
-- precies deze parameters, geeft text terug. recht: wie de functie mag aanroepen (na 0047: geen; na 0048: authenticated).
begin;
with f as (select p.* from pg_proc p where p.oid = to_regprocedure('public.bon_ondertekenen(uuid,text,text,text)')),
v as (select '083a2f1e742d35d6438bd70fad8d467d'::text as verwacht)
select case when not exists (select 1 from f) then 'ONTBREEKT'
  when (select md5(btrim(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g'))) from f) = v.verwacht then 'GELIJK'
  else 'AFWIJKEND' end as oordeel,
 (select md5(btrim(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g'))) from f) as code_md5,
 v.verwacht,
 coalesce((select prosecdef and pg_get_userbyid(proowner) = 'postgres' and coalesce(proconfig::text, '') = '{"search_path=public, pg_temp"}'
   and proargnames::text = '{p_bon,p_naam,p_handtekening,p_vingerafdruk}' and prorettype = 'text'::regtype and prolang = (select oid from pg_language where lanname = 'plpgsql')
   from f), false) as kenmerken_ok,
 coalesce((select coalesce(proacl::text, '') from f), '') as recht,
 (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'bon_ondertekenen') as aantal_versies
from v;
rollback;
