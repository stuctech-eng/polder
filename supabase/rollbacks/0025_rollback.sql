-- Rollback 0025. EERST de app terugzetten (de nieuwe app roept my_access() aan), dan dit.
-- Draait alleen als alles exact in de 0025-stand staat en GEEN restaurant uit staat; anders afbreken, niets gewijzigd.
begin;
do $m$ begin
if md5(btrim(regexp_replace((select prosrc from pg_proc where oid=to_regprocedure('public.my_restaurant_id()')),'\s+',' ','g')))
  is distinct from '2aaa6bdf8477d9363fd7dc01842e9cb8'
or md5(btrim(regexp_replace((select prosrc from pg_proc where oid=to_regprocedure('public.my_role()')),'\s+',' ','g')))
  is distinct from 'd84c30bd34f0b43c39b6ec31b7925ea5'
or md5(btrim(regexp_replace((select prosrc from pg_proc where oid=to_regprocedure('public.my_access()')),'\s+',' ','g')))
  is distinct from 'c174980d3cf34922d80df7cd2b9c50db'
or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='restaurants' and column_name='is_active') then
  raise exception '0025-rollback vooraf: stand wijkt af van 0025, niets teruggedraaid';
end if;
if exists (select 1 from public.restaurants where not is_active) then
  raise exception '0025-rollback: er staat een restaurant uit; eerst bewust weer aanzetten, niets teruggedraaid';
end if; end $m$;

create or replace function public.my_restaurant_id() returns uuid language sql stable security definer
set search_path = public, pg_temp as $$
  select u.restaurant_id from public.users u where u.id = auth.uid() and u.is_active
$$;

create or replace function public.my_role() returns text language sql stable security definer
set search_path = public, pg_temp as $$
  select u.role from public.users u where u.id = auth.uid() and u.is_active
$$;

drop function public.my_access();
alter table public.restaurants drop column is_active;

do $m$ begin
if md5(btrim(regexp_replace((select prosrc from pg_proc where oid=to_regprocedure('public.my_restaurant_id()')),'\s+',' ','g')))
  is distinct from 'dd3c18c75a9cbebfcd720d59059c5915'
or md5(btrim(regexp_replace((select prosrc from pg_proc where oid=to_regprocedure('public.my_role()')),'\s+',' ','g')))
  is distinct from 'f41f0b9bc00f23f62258cd703aad7844' then
  raise exception '0025-rollback achteraf: functies niet gelijk aan 0015, niets teruggedraaid';
end if; end $m$;
commit;
