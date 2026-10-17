-- 0043 handtekening (14c, 1/6): module signature (standaard uit) + vingerafdruk van een bon. Na 0042. Rollback: rollbacks/0043_rollback.sql
-- Wijzigt geen bestaande functie, wacht of data.
begin;
do $m$ begin
if to_regprocedure('public.feature_aan(uuid,text)') is null or to_regprocedure('public.bon_indienen(uuid,text)') is null
  or not exists (select 1 from pg_trigger where tgname = 'receipts_pin_wacht')
  or exists (select 1 from public.features where key = 'signature') or exists (select 1 from public.restaurant_features where feature = 'signature')
  or to_regproc('public.bon_vingerafdruk') is not null
  or exists (select 1 from public.approval_settings where method = 'signature') or exists (select 1 from public.approvals where method = 'signature')
then raise exception '0043 vooraf: stand wijkt af, niets gewijzigd'; end if; end $m$;

insert into public.features (key, default_enabled, description) values ('signature', false, 'Handtekening klant');

-- wat de klant ondertekent: bon, bedrijf van de rekening, wachtende regel(s), productregels. Als de gebruiker (RLS).
create function public.bon_vingerafdruk(p_bon uuid) returns text language sql stable security invoker
set search_path = public, pg_temp as $f$
  select md5(concat_ws('|', b.id, b.receipt_number, b.total, b.status, (select company_id from open_tabs where id = b.open_tab_id),
    (select string_agg(concat_ws(':', a.id, a.method, a.company_id), ',' order by a.id) from approvals a
      where a.receipt_id = b.id and a.status = 'pending'),
    (select string_agg(concat_ws(':', l.id, l.description, l.quantity, l.unit_price, l.vat_rate, l.line_total), ',' order by l.id)
      from receipt_lines l where l.receipt_id = b.id)))
  from receipts b where b.id = p_bon
$f$;

revoke all on function public.bon_vingerafdruk(uuid) from public, anon, authenticated, service_role;
grant execute on function public.bon_vingerafdruk(uuid) to authenticated;

do $m$ begin
if (select count(*) from public.features where key = 'signature' and not default_enabled) <> 1
  or exists (select 1 from public.restaurants r where public.feature_aan(r.id, 'signature'))
  or (select count(*) from pg_proc where oid = to_regprocedure('public.bon_vingerafdruk(uuid)') and not prosecdef
      and pg_get_userbyid(proowner) = 'postgres' and proconfig = '{"search_path=public, pg_temp"}'
      and proacl::text = '{postgres=X/postgres,authenticated=X/postgres}') <> 1
then raise exception '0043 achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
