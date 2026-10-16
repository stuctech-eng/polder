-- 0041 bon indienen in een keer (stap 14a, deel 5 van 6). Na 0040. Rollback: rollbacks/0041_rollback.sql
-- Bon op pending_approval + goedkeuringsregel met de methode uit de bedrijfsinstelling, in EEN transactie: lukt een deel niet,
-- dan verandert er niets (geen bon die wacht zonder regel). SECURITY INVOKER: draait als de gebruiker, met dezelfde RLS en
-- wachten als nu. Wijzigt de instelling tegelijk, dan weigert approvals_pin_wacht (0040) de regel en draait alles terug.
begin;
do $m$ begin
if to_regprocedure('public.approvals_pin_wacht()') is null or to_regprocedure('public.bon_indienen(uuid,text)') is not null
  or exists (select 1 from pg_trigger where tgname = 'receipts_pin_wacht')
then raise exception '0041 vooraf: 0040 ontbreekt of 0041/0042 bestaat al, niets gewijzigd'; end if; end $m$;

-- geeft de methode terug; null = goedkeuring staat voor dit bedrijf uit (dan niets gewijzigd)
create function public.bon_indienen(p_bon uuid, p_token text) returns text language plpgsql security invoker
set search_path = public, pg_temp as $f$
declare c uuid; m text; aan boolean;
begin
  select t.company_id into c from receipts b join open_tabs t on t.id = b.open_tab_id where b.id = p_bon;
  if not found then raise exception 'Bon niet gevonden' using errcode = 'no_data_found'; end if;
  if c is null then raise exception 'Bon heeft geen gekoppeld bedrijf' using errcode = 'check_violation'; end if;
  select is_required, method into aan, m from approval_settings where company_id = c;
  if not coalesce(aan, false) or m is null then return null; end if;
  update receipts set status = 'pending_approval' where id = p_bon and status in ('draft', 'linked');
  if not found then raise exception 'Bon kan niet (meer) worden ingediend' using errcode = 'check_violation'; end if;
  insert into approvals (receipt_id, company_id, method, status, verification_code)
    values (p_bon, c, m, 'pending', case when m in ('email', 'qr') then p_token end);
  return m;
end $f$;

revoke all on function public.bon_indienen(uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.bon_indienen(uuid, text) to authenticated;

do $m$ begin
if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'bon_indienen' and not prosecdef
    and pg_get_userbyid(proowner) = 'postgres' and proconfig = '{"search_path=public, pg_temp"}'
    and (select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text) from aclexplode(proacl) x) = 'authenticated,postgres') <> 1
then raise exception '0041 achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
