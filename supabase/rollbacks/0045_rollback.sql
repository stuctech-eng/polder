-- 0045 rollback (14c): approvals_guard terug naar de tekst van voor 0045. Na het terugdraaien van 0046-0048. Precies omgekeerd aan 0045.
begin;
do $m$
declare
  o text := $t$if not (public.has_perm('APPROVE_RECEIPTS') or current_user = 'service_role'
          or (new.status = 'approved' and current_user = 'postgres'
              and coalesce(current_setting('polder.ondertekening', true), '') = new.receipt_id::text)) then$t$;
  n text := $t$if not (public.has_perm('APPROVE_RECEIPTS') or current_user = 'service_role') then$t$;
  s text; a text; r text; v text;
begin
  select md5(btrim(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g'))), coalesce(proacl::text, ''), prosrc
    into a, r, s from pg_proc where oid = 'public.approvals_guard()'::regprocedure
    and not prosecdef and proconfig = '{"search_path=public, pg_temp"}' and pg_get_userbyid(proowner) = 'postgres';
  if to_regprocedure('public.teken_wacht()') is not null or a is distinct from 'f09a6668e335cec5c620de438bd7a5eb' or array_length(string_to_array(s, o), 1) <> 2 then
    raise exception '0045 rollback vooraf: stand wijkt af, niets gewijzigd'; end if;
  execute format('create or replace function public.approvals_guard() returns trigger language plpgsql set search_path = public, pg_temp as %L',
    replace(s, o, n));
  select md5(btrim(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g'))), coalesce(proacl::text, '')
    into a, v from pg_proc where oid = 'public.approvals_guard()'::regprocedure
    and not prosecdef and proconfig = '{"search_path=public, pg_temp"}' and pg_get_userbyid(proowner) = 'postgres';
  if a is distinct from 'd84e5483f3bad1bcb48aa443a2e16644' or v is distinct from r then raise exception '0045 rollback achteraf: controle mislukt, niets gewijzigd'; end if;
end $m$;
commit;
