-- Alleen LOKAAL (PostgreSQL 17): nabootsing van de productiestand zoals gemeten in stap 13a (14 okt 2026,
-- prod-rechten-inventaris.sql). Na local-build.sh t/m 0035. Niet op productie of staging draaien.
-- Bewijs: prod-rechten-inventaris.sql geeft hierna regel voor regel dezelfde uitvoer als productie (zie rechten-tests.sh).
do $$ begin
  if current_setting('server_version_num')::int < 170000 then
    raise exception 'local-prod17-stand: alleen PostgreSQL 17 of nieuwer (productie draait 17.6, recht MAINTAIN)';
  end if;
end $$;

-- 1. email_settings bestaat in productie niet (migratie 0002 is daar nooit uitgevoerd)
drop table if exists public.email_settings;

-- 2. uitbreidingen staan in productie niet in public (35 eigen functies), maar in het schema extensions
create schema if not exists extensions;
alter extension pgcrypto set schema extensions;
alter extension "uuid-ossp" set schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;
do $$ begin
  execute format('alter database %I set search_path = "$user", public, extensions', current_database());
end $$;

-- 3. standaardrechten van postgres in public, exact zoals gemeten
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on tables to postgres;
alter default privileges for role postgres in schema public grant maintain on tables to anon;
alter default privileges for role postgres in schema public
  grant select, insert, update, delete, maintain on tables to authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to postgres;
alter default privileges for role postgres in schema public grant select, usage on sequences to authenticated, service_role;
alter default privileges for role postgres in schema public grant execute on functions to postgres;

-- 4. supabase_admin en zijn (ruime) standaardrechten in public, exact zoals gemeten
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_admin') then create role supabase_admin nologin; end if;
end $$;
alter default privileges for role supabase_admin in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public grant all on sequences to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public grant all on functions to postgres, anon, authenticated, service_role;

-- 5. rls_auto_enable(): in productie een Supabase-functie (event trigger, security definer) die RLS aanzet op nieuwe
--    tabellen in public. Hier een eenvoudige nabootsing; de echte functie wordt nooit gewijzigd.
create or replace function public.rls_auto_enable() returns event_trigger
language plpgsql security definer set search_path = pg_catalog as $$
declare o record;
begin
  for o in select * from pg_event_trigger_ddl_commands()
           where command_tag = 'CREATE TABLE' and schema_name = 'public' loop
    execute format('alter table %s enable row level security', o.object_identity);
  end loop;
end $$;
drop event trigger if exists rls_auto_enable;
create event trigger rls_auto_enable on ddl_command_end when tag in ('CREATE TABLE') execute function public.rls_auto_enable();
