-- POLDER — controle platformbeheer (migraties 0026 + 0027). ALLEEN LEZEN, eindigt met rollback.
-- Vóór 0026: 0025/nee/nee/nee/leeg/leeg/nee/leeg. Na 0026: 0025/ja/ja/ja/ja/true/nee/0. Na 0027: acties "ja".
-- beheerders = aantal toegevoegde beheerders (na de migraties 0, na het toevoegen 1).
begin;
select
  case md5(btrim(regexp_replace((select prosrc from pg_proc where oid = to_regprocedure('public.my_access()')), '\s+', ' ', 'g')))
    when 'c174980d3cf34922d80df7cd2b9c50db' then '0025' else 'ONBEKEND' end as my_access,
  case when to_regclass('public.platform_admins') is null then 'nee' else 'ja' end as platform_admins,
  case when to_regclass('public.platform_log') is null then 'nee' else 'ja' end as platform_log,
  case when to_regprocedure('public.is_platform_admin()') is null then 'nee' else 'ja' end as is_platform_admin,
  case when to_regclass('public.platform_log') is null then null
    when (select bool_and(relrowsecurity) from pg_class where oid in (to_regclass('public.platform_admins'), to_regclass('public.platform_log')))
    then 'ja' else 'NEE' end as rls,
  case when to_regclass('public.platform_log') is null then null else
    not has_table_privilege('authenticated', 'public.platform_admins', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('authenticated', 'public.platform_log', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('anon', 'public.platform_log', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('service_role', 'public.platform_log', 'INSERT,UPDATE,DELETE,TRUNCATE')
    and not has_function_privilege('anon', 'public.is_platform_admin()', 'EXECUTE') end as rechten_ok,
  case when to_regprocedure('public.platform_restaurant_status(uuid,uuid,boolean)') is null then 'nee'
    when (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'platform\_%'
      and p.prosecdef and has_function_privilege('service_role', p.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')) = 3
    then 'ja' else 'AFWIJKEND' end as acties,
  case when to_regclass('public.platform_admins') is null then null
    else (xpath('/row/n/text()', query_to_xml('select count(*) as n from public.platform_admins', false, true, '')))[1]::text::int
  end as beheerders;
rollback;
