-- 0026 platformbeheer (docs/architecture.md 13.19). Daarna 0027, dan de app. Rollback: rollbacks/0026_rollback.sql
begin;
do $m$ begin
if md5(btrim(regexp_replace((select prosrc from pg_proc where oid=to_regprocedure('public.my_access()')),'\s+',' ','g')))
  is distinct from 'c174980d3cf34922d80df7cd2b9c50db'
or to_regclass('public.platform_admins') is not null or to_regclass('public.platform_log') is not null
or to_regprocedure('public.is_platform_admin()') is not null then
  raise exception '0026 vooraf: uitgangsstand wijkt af (0025 ontbreekt of 0026 al uitgevoerd), niets gewijzigd';
end if; end $m$;

create table public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.platform_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  admin_user_id uuid not null,
  action text not null check (action in ('restaurant_aangemaakt','restaurant_aan','restaurant_uit','eigenaar_uitgenodigd')),
  restaurant_id uuid,
  details jsonb not null default '{}'::jsonb
);
alter table public.platform_admins enable row level security;
alter table public.platform_log enable row level security;
revoke all on public.platform_admins, public.platform_log from public, anon, authenticated, service_role;
grant select on public.platform_admins to service_role;
grant select on public.platform_log to service_role;

create function public.is_platform_admin() returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select exists (select 1 from public.platform_admins p where p.user_id = auth.uid() and p.is_active)
$$;
revoke all on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated, service_role;

do $m$ begin
if not (select relrowsecurity from pg_class where oid = 'public.platform_admins'::regclass)
or not (select relrowsecurity from pg_class where oid = 'public.platform_log'::regclass)
or exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('platform_admins','platform_log'))
or has_table_privilege('authenticated', 'public.platform_admins', 'SELECT,INSERT,UPDATE,DELETE')
or has_table_privilege('authenticated', 'public.platform_log', 'SELECT,INSERT,UPDATE,DELETE')
or has_table_privilege('anon', 'public.platform_log', 'SELECT,INSERT,UPDATE,DELETE')
or has_table_privilege('service_role', 'public.platform_log', 'INSERT,UPDATE,DELETE,TRUNCATE')
or has_table_privilege('service_role', 'public.platform_admins', 'INSERT,UPDATE,DELETE,TRUNCATE')
or has_function_privilege('anon', 'public.is_platform_admin()', 'EXECUTE')
or exists (select 1 from public.platform_admins) then
  raise exception '0026 achteraf: controle mislukt, niets gewijzigd';
end if; end $m$;
commit;
