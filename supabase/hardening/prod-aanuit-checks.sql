-- POLDER — controle restaurant aan/uit (migratie 0025). ALLEEN LEZEN, eindigt met rollback.
-- Verwacht vóór 0025: functies "0015", kolom/my_access "nee". Verwacht na 0025: functies "0025", kolom/my_access "ja",
-- restaurants_uit 0, anon_my_access false, dekking_buiten_helpers leeg.
begin;
select
  case md5(btrim(regexp_replace((select prosrc from pg_proc where oid = to_regprocedure('public.my_restaurant_id()')), '\s+', ' ', 'g')))
    when 'dd3c18c75a9cbebfcd720d59059c5915' then '0015' when '2aaa6bdf8477d9363fd7dc01842e9cb8' then '0025' else 'ONBEKEND' end as my_restaurant_id,
  case md5(btrim(regexp_replace((select prosrc from pg_proc where oid = to_regprocedure('public.my_role()')), '\s+', ' ', 'g')))
    when 'f41f0b9bc00f23f62258cd703aad7844' then '0015' when 'd84c30bd34f0b43c39b6ec31b7925ea5' then '0025' else 'ONBEKEND' end as my_role,
  case when to_regprocedure('public.my_access()') is null then 'nee'
    when md5(btrim(regexp_replace((select prosrc from pg_proc where oid = to_regprocedure('public.my_access()')), '\s+', ' ', 'g')))
      = 'c174980d3cf34922d80df7cd2b9c50db' then 'ja' else 'ONBEKEND' end as my_access,
  case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'restaurants'
    and column_name = 'is_active') then 'ja' else 'nee' end as kolom_is_active,
  (select count(*) from public.restaurants r where (to_jsonb(r) ->> 'is_active') = 'false') as restaurants_uit,
  case when to_regprocedure('public.my_access()') is null then null
    else has_function_privilege('anon', 'public.my_access()', 'EXECUTE') end as anon_my_access,
  (select string_agg(schemaname || '.' || tablename || ' ' || policyname, '; ') from pg_policies
    where schemaname in ('public', 'storage') and coalesce(qual, '') || coalesce(with_check, '') !~ 'my_restaurant_id|has_perm'
      and not (tablename = 'users' and policyname = 'users can see own profile')) as dekking_buiten_helpers;
rollback;
