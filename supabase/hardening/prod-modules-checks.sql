-- POLDER — controle modules per restaurant (migraties 0028-0030). ALLEEN LEZEN, eindigt met rollback.
-- Vóór 0028: 0027/nee/nee/nee/0/nee/leeg/leeg + guards_md5 noteren. Na 0030: 0027/ja/ja/ja/6/ja/true/true + guards_md5 ONGEWIJZIGD.
begin;
select
  case md5(btrim(regexp_replace((select prosrc from pg_proc where oid = to_regprocedure('public.platform_restaurant_status(uuid,uuid,boolean)')), '\s+', ' ', 'g')))
    when 'cb78b3d569496a1f675ed9fec4738633' then '0027' else 'ONBEKEND' end as platform_0027,
  case when to_regclass('public.restaurant_features') is null then 'nee' else 'ja' end as register_0028,
  case when to_regprocedure('public.platform_module_zetten(uuid,uuid,text,boolean)') is null then 'nee' else 'ja' end as beheer_0029,
  case when to_regprocedure('public.module_wacht()') is null then 'nee' else 'ja' end as wacht_0030,
  (select count(*) from pg_trigger where tgname = 'module_wacht') as wacht_triggers,
  case when (select pg_get_constraintdef(oid) from pg_constraint where conname = 'platform_log_action_check') like '%module_uit%'
    then 'ja' else 'nee' end as logboek_modules,
  case when to_regprocedure('public.my_feature(text)') is null then null else
    not has_function_privilege('authenticated', 'public.feature_aan(uuid,text)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.my_feature(text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.my_feature(text)', 'EXECUTE')
    and not has_table_privilege('authenticated', 'public.restaurant_features', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('anon', 'public.restaurant_features', 'SELECT,INSERT,UPDATE,DELETE')
    and (select bool_and(prosecdef and proconfig = '{"search_path=public, pg_temp"}') from pg_proc
         where pronamespace = 'public'::regnamespace and proname in ('feature_aan','my_feature','platform_module_zetten','module_wacht'))
  end as rechten_ok,
  case when to_regprocedure('public.feature_aan(uuid,text)') is null then null else
    (xpath('/row/b/text()', query_to_xml('select bool_and(public.feature_aan(r.id, k)) as b from public.restaurants r cross join
      (values (''daily_closing''),(''payment_registration''),(''approval'')) v(k)', false, true, '')))[1]::text::boolean
  end as alles_aan,
  (select md5(string_agg(p.proname || md5(p.prosrc), '|' order by p.proname)) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prorettype = 'trigger'::regtype and p.proname <> 'module_wacht') as guards_md5;
rollback;
