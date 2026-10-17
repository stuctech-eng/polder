-- POLDER controle 14c 0043-0048, ALLEEN LEZEN. ONBEKEND=gat. wachten 0046+: 2. wachten_md5: approvals_guard,receipts_guard
-- bestaand_md5: steeds gelijk
begin;
with b as (select (exists (select 1 from features where key = 'signature'))::int::text
 || (position('polder.ondertekening' in (select prosrc from pg_proc where oid = 'public.receipts_guard()'::regprocedure)) > 0)::int::text
 || (position('polder.ondertekening' in (select prosrc from pg_proc where oid = 'public.approvals_guard()'::regprocedure)) > 0)::int::text
 || (to_regproc('public.teken_wacht') is not null)::int::text
 || (to_regproc('public.bon_ondertekenen') is not null)::int::text
 || coalesce(has_function_privilege('authenticated', to_regproc('public.bon_ondertekenen'), 'execute'), false)::int::text as s)
select case b.s when '000000' then '0042' when '100000' then '0043' when '110000' then '0044' when '111000' then '0045' when '111100' then '0046'
 when '111110' then '0047' when '111111' then '0048' else 'ONBEKEND' end as stand, b.s as bits,
 not exists (select 1 from pg_proc where pronamespace='public'::regnamespace and proname in ('bon_vingerafdruk','teken_wacht','bon_ondertekenen','png_geldig')
  and not(prosecdef = (proname = 'bon_ondertekenen') and pg_get_userbyid(proowner) = 'postgres' and coalesce(proconfig::text,'') = '{"search_path=public, pg_temp"}'
  and coalesce(proacl::text,'') = case when proname = 'bon_vingerafdruk' or proname = 'bon_ondertekenen' and has_function_privilege('authenticated', oid, 'execute')
  then '{postgres=X/postgres,authenticated=X/postgres}' else '{postgres=X/postgres}' end)) and not exists (select 1 from features where key = 'signature' and default_enabled) as nieuw_ok,
 (select count(*) from pg_trigger where tgname like '%teken\_wacht') as wachten,
 (select string_agg(left(md5(btrim(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g'))), 6), ',' order by proname)
  from pg_proc where oid in ('public.receipts_guard()'::regprocedure, 'public.approvals_guard()'::regprocedure)) as wachten_md5,
 md5(concat_ws('|',
 (select string_agg(proname||md5(prosrc)||coalesce(proacl::text,'')||prosecdef||coalesce(proconfig::text,''),',' order by proname,md5(prosrc))
 from pg_proc where pronamespace='public'::regnamespace and proname not in ('receipts_guard','approvals_guard','bon_vingerafdruk','teken_wacht','bon_ondertekenen','png_geldig')),
 (select string_agg(pg_get_triggerdef(oid),',' order by pg_get_triggerdef(oid)) from pg_trigger where not tgisinternal and tgname not like '%teken\_wacht'),
 (select string_agg(tablename||policyname||cmd||coalesce(qual,'')||coalesce(with_check,''),',' order by tablename,policyname) from pg_policies),
 (select string_agg(c.relname||coalesce(c.relacl::text,''),',' order by c.relname) from pg_class c where c.relnamespace='public'::regnamespace),
 (select string_agg(defaclacl::text,',' order by defaclacl::text) from pg_default_acl))) as bestaand_md5
from b;
rollback;
