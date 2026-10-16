-- POLDER controle 14a 0037-0042, ALLEEN LEZEN. ONBEKEND=gat. wachten: 0040/0041=2, 0042=3.
-- bestaand_md5 (steeds gelijk): functies/triggers/policies/rechten, niet kolommen/constraints/indexen.
begin;
with b as (select (to_regclass('public.pin_reserveringen') is not null)::int::text
 || (to_regprocedure('public.pin_poging_afronden(uuid,boolean)') is not null)::int::text
 || (to_regprocedure('public.pin_poging_start(uuid,uuid)') is not null)::int::text
 || (exists (select 1 from pg_trigger where tgname = 'approvals_pin_wacht'))::int::text
 || (to_regprocedure('public.bon_indienen(uuid,text)') is not null)::int::text
 || (exists (select 1 from pg_trigger where tgname = 'receipts_pin_wacht'))::int::text as s)
select case b.s when '000000' then '0036' when '100000' then '0037' when '110000' then '0038' when '111000' then '0039'
 when '111100' then '0040' when '111110' then '0041' when '111111' then '0042' else 'ONBEKEND' end as stand, b.s as bits,
 not exists (select 1 from pg_proc where pronamespace='public'::regnamespace and (proname like 'pin\_%' or proname like '%pin\_wacht' or proname='bon_indienen')
 and not (prosecdef=(proname<>'bon_indienen') and pg_get_userbyid(proowner)='postgres' and proconfig='{"search_path=public, pg_temp"}'
 and (select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text) from aclexplode(proacl) x)
 = case when proname like '%wacht' then 'postgres' when proname='bon_indienen' then 'authenticated,postgres' else 'postgres,service_role' end))
 and not exists (select 1 from pg_class c left join aclexplode(c.relacl) x on true where c.relnamespace='public'::regnamespace
 and c.relname like 'pin\_%' and (x.grantee<>c.relowner or c.relkind='r' and not c.relrowsecurity))
 and not exists (select 1 from pg_policies where tablename like 'pin\_%') as nieuw_ok,
 (select count(*) from pg_trigger where tgname like '%pin\_wacht') as wachten,
 md5(concat_ws('|',
 (select string_agg(proname||md5(prosrc)||coalesce(proacl::text,'')||prosecdef||coalesce(proconfig::text,''),',' order by proname,md5(prosrc))
 from pg_proc where pronamespace='public'::regnamespace and proname not like 'pin\_%' and proname not like '%pin\_wacht' and proname<>'bon_indienen'),
 (select string_agg(pg_get_triggerdef(oid),',' order by pg_get_triggerdef(oid)) from pg_trigger where not tgisinternal and tgname not like '%pin\_wacht'),
 (select string_agg(tablename||policyname||cmd||coalesce(qual,'')||coalesce(with_check,''),',' order by tablename,policyname) from pg_policies),
 (select string_agg(c.relname||coalesce(c.relacl::text,'')||coalesce(a.x,''),',' order by c.relname) from pg_class c left join lateral
 (select string_agg(attname||attacl::text,',' order by attname) x from pg_attribute where attrelid=c.oid and attacl is not null) a on true
 where c.relnamespace='public'::regnamespace and c.relname not like 'pin\_%'),
 (select string_agg(defaclacl::text,',' order by defaclacl::text) from pg_default_acl))) as bestaand_md5
from b;
rollback;
