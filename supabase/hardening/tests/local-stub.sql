-- ============================================================
-- Alleen voor een LOKALE Postgres-testdatabase (geen Supabase): minimale nabootsing van auth/storage.
-- Op een echt Supabase-staging-project NIET draaien (daar bestaan auth en storage al).
-- ============================================================
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;
do $$ begin
 if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
 if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
 if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema auth;
create table auth.users(id uuid primary key default gen_random_uuid(), email text,
  instance_id uuid, aud text, role text, encrypted_password text, email_confirmed_at timestamptz, created_at timestamptz, updated_at timestamptz,
  confirmation_token text, recovery_token text, email_change text, email_change_token_new text, email_change_token_current text,
  raw_app_meta_data jsonb, raw_user_meta_data jsonb, is_super_admin boolean, is_sso_user boolean default false, last_sign_in_at timestamptz, banned_until timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
create schema storage;
create table storage.buckets(id text primary key, name text, public boolean);
create table storage.objects(id uuid default gen_random_uuid(), bucket_id text references storage.buckets(id), name text, owner uuid, metadata jsonb);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql as $$ select (string_to_array(name,'/'))[1:greatest(array_length(string_to_array(name,'/'),1)-1,0)] $$;
