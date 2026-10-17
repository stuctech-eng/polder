-- 0045 handtekening (14c, 3/6): smalle uitzondering in approvals_guard. Na 0044. Rollback: rollbacks/0045_rollback.sql
-- Precies EEN voorwaarde wordt uitgebreid (moet precies 1x voorkomen); de rest blijft de tekst die nu in de database staat.
-- Uitzondering alleen als: uitvoerende rol postgres (eigenaar van bon_ondertekenen, 0047) EN markering polder.ondertekening =
-- id van DEZE bon (NULL-veilig: geen markering = weigeren). Alleen regel -> approved.
-- Vingerafdruk zonder commentaar en witruimte: vooraf exact de huidige stand (0022), achteraf exact de nieuwe. Rechten blijven gelijk.
begin;
do $m$
declare
  o text := $t$if not (public.has_perm('APPROVE_RECEIPTS') or current_user = 'service_role') then$t$;
  n text := $t$if not (public.has_perm('APPROVE_RECEIPTS') or current_user = 'service_role'
          or (new.status = 'approved' and current_user = 'postgres'
              and coalesce(current_setting('polder.ondertekening', true), '') = new.receipt_id::text)) then$t$;
  s text; a text; r text; v text;
begin
  select md5(btrim(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g'))), coalesce(proacl::text, ''), prosrc
    into a, r, s from pg_proc where oid = 'public.approvals_guard()'::regprocedure
    and not prosecdef and proconfig = '{"search_path=public, pg_temp"}' and pg_get_userbyid(proowner) = 'postgres';
  if to_regprocedure('public.bon_vingerafdruk(uuid)') is null or to_regprocedure('public.teken_wacht()') is not null
    or position('polder.ondertekening' in pg_get_functiondef('public.receipts_guard()'::regprocedure)) = 0 or a is distinct from 'd84e5483f3bad1bcb48aa443a2e16644' or array_length(string_to_array(s, o), 1) <> 2 then
    raise exception '0045 vooraf: stand wijkt af, niets gewijzigd'; end if;
  execute format('create or replace function public.approvals_guard() returns trigger language plpgsql set search_path = public, pg_temp as %L',
    replace(s, o, n));
  select md5(btrim(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g'))), coalesce(proacl::text, '')
    into a, v from pg_proc where oid = 'public.approvals_guard()'::regprocedure
    and not prosecdef and proconfig = '{"search_path=public, pg_temp"}' and pg_get_userbyid(proowner) = 'postgres';
  if a is distinct from 'f09a6668e335cec5c620de438bd7a5eb' or v is distinct from r then raise exception '0045 achteraf: controle mislukt, niets gewijzigd'; end if;
end $m$;
commit;
