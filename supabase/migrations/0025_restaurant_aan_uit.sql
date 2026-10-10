-- 0025 restaurant aan/uit (docs/architecture.md 13.18). Eerst deze migratie, daarna de app. Rollback: rollbacks/0025_rollback.sql
begin;
do $m$ begin
if md5(btrim(regexp_replace((select prosrc from pg_proc where oid=to_regprocedure('public.my_restaurant_id()')),'\s+',' ','g')))
  is distinct from 'dd3c18c75a9cbebfcd720d59059c5915'
or md5(btrim(regexp_replace((select prosrc from pg_proc where oid=to_regprocedure('public.my_role()')),'\s+',' ','g')))
  is distinct from 'f41f0b9bc00f23f62258cd703aad7844'
or exists (select 1 from information_schema.columns where table_schema='public' and table_name='restaurants' and column_name='is_active')
or to_regprocedure('public.my_access()') is not null then
  raise exception '0025 vooraf: uitgangsstand wijkt af (al uitgevoerd of functies niet gelijk aan 0015), niets gewijzigd';
end if; end $m$;

alter table public.restaurants add column is_active boolean not null default true;

create or replace function public.my_restaurant_id() returns uuid language sql stable security definer
set search_path = public, pg_temp as $$
  select u.restaurant_id from public.users u join public.restaurants r on r.id = u.restaurant_id
  where u.id = auth.uid() and u.is_active and r.is_active
$$;

create or replace function public.my_role() returns text language sql stable security definer
set search_path = public, pg_temp as $$
  select u.role from public.users u join public.restaurants r on r.id = u.restaurant_id
  where u.id = auth.uid() and u.is_active and r.is_active
$$;

create function public.my_access() returns text language sql stable security definer
set search_path = public, pg_temp as $$
  select case when auth.uid() is null then 'niet_ingelogd' when u.id is null then 'geen_profiel'
    when not u.is_active then 'gebruiker_uit' when not r.is_active then 'restaurant_uit' else 'ok' end
  from (select 1) x left join public.users u on u.id = auth.uid() left join public.restaurants r on r.id = u.restaurant_id
$$;
revoke all on function public.my_access() from public, anon;
grant execute on function public.my_access() to authenticated, service_role;

do $m$ begin
if (select count(*) from pg_proc where oid in (to_regprocedure('public.my_restaurant_id()'), to_regprocedure('public.my_role()'),
      to_regprocedure('public.my_access()')) and prosecdef and proconfig = '{"search_path=public, pg_temp"}') <> 3
or has_function_privilege('anon', 'public.my_access()', 'EXECUTE')
or not has_function_privilege('authenticated', 'public.my_access()', 'EXECUTE')
or exists (select 1 from public.restaurants where not is_active) then
  raise exception '0025 achteraf: controle mislukt, niets gewijzigd';
end if; end $m$;
commit;
