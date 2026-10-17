-- 0044 handtekening (14c, 2/6): smalle uitzondering in receipts_guard. Na 0043. Rollback: rollbacks/0044_rollback.sql
-- Precies EEN voorwaarde wordt uitgebreid (moet precies 1x voorkomen); de rest blijft de tekst die nu in de database staat.
-- Uitzondering alleen als: uitvoerende rol postgres (eigenaar van bon_ondertekenen, 0047) EN markering polder.ondertekening =
-- id van DEZE bon (NULL-veilig: geen markering = weigeren). Alleen bon pending_approval -> approved/locked.
-- Vingerafdruk zonder commentaar en witruimte: vooraf exact de huidige stand (0021), achteraf exact de nieuwe. Rechten blijven gelijk.
begin;
do $m$
declare
  o text := $t$if not (v_can_approve or (v_public_link and old.status = 'pending_approval' and new.status = 'locked')) then$t$;
  n text := $t$if not (v_can_approve or (v_public_link and old.status = 'pending_approval' and new.status = 'locked')
          or (old.status = 'pending_approval' and current_user = 'postgres'
              and coalesce(current_setting('polder.ondertekening', true), '') = new.id::text)) then$t$;
  s text; a text; r text; v text;
begin
  select md5(btrim(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g'))), coalesce(proacl::text, ''), prosrc
    into a, r, s from pg_proc where oid = 'public.receipts_guard()'::regprocedure
    and not prosecdef and proconfig = '{"search_path=public, pg_temp"}' and pg_get_userbyid(proowner) = 'postgres';
  if to_regprocedure('public.bon_vingerafdruk(uuid)') is null or to_regprocedure('public.teken_wacht()') is not null or a is distinct from '9d354007792cafce14805130ce339227' or array_length(string_to_array(s, o), 1) <> 2 then
    raise exception '0044 vooraf: stand wijkt af, niets gewijzigd'; end if;
  execute format('create or replace function public.receipts_guard() returns trigger language plpgsql set search_path = public, pg_temp as %L',
    replace(s, o, n));
  select md5(btrim(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g'))), coalesce(proacl::text, '')
    into a, v from pg_proc where oid = 'public.receipts_guard()'::regprocedure
    and not prosecdef and proconfig = '{"search_path=public, pg_temp"}' and pg_get_userbyid(proowner) = 'postgres';
  if a is distinct from '50feb65c86fb9683e93177479acd9965' or v is distinct from r then raise exception '0044 achteraf: controle mislukt, niets gewijzigd'; end if;
end $m$;
commit;
