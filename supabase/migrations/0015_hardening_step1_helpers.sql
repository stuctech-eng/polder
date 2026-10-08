-- ============================================================
-- Migratie 0015 — SECURITY HARDENING STAP 1 (H1 + H9): databasehelpers
-- Plan: docs/security-hardening-plan.md sectie 2. Alleen functies; GEEN policies, triggers,
-- tabelrechten, storage of data worden gewijzigd.
--
--  * my_restaurant_id(): zelfde semantiek, maar vast search_path, gekwalificeerde namen en
--    alleen een ACTIEVE gebruiker (fail closed: geen uid / geen profiel / inactief → NULL).
--  * NIEUW my_role(), role_has_permission(role, perm), has_perm(perm).
--    role_has_permission is een exacte kopie van PERMISSIONS in lib/user-management/role-helpers.ts.
--  * EXECUTE: niet voor PUBLIC/anon; wel voor authenticated en service_role.
--  rls_auto_enable() en alle andere functies blijven ongemoeid.
-- Rollback: supabase/rollbacks/0015_rollback.sql
-- ============================================================
begin;

do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'users' and column_name = 'is_active') then
    raise exception 'public.users.is_active ontbreekt — migratie 0008 eerst draaien';
  end if;
end $$;

-- 1. my_restaurant_id(): bestaande functie, nu veilig en fail-closed
create or replace function public.my_restaurant_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select u.restaurant_id from public.users u where u.id = auth.uid() and u.is_active
$$;

-- 2. my_role(): rol van de ingelogde, actieve gebruiker (anders NULL)
create or replace function public.my_role()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select u.role from public.users u where u.id = auth.uid() and u.is_active
$$;

-- 3. role_has_permission(): exacte kopie van PERMISSIONS (TypeScript). Onbekende/NULL rol of permissie → false.
create or replace function public.role_has_permission(p_role text, p_perm text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select coalesce(
    case p_perm
      when 'VIEW_DASHBOARD'        then p_role in ('owner','manager','administratie')
      when 'VIEW_REVENUE'          then p_role in ('owner','manager','administratie')
      when 'MANAGE_COMPANIES'      then p_role in ('owner','administratie')
      when 'MANAGE_OPEN_TABS'      then p_role in ('owner','manager','administratie','bediening')
      when 'MANAGE_RECEIPTS'       then p_role in ('owner','manager','administratie','bediening')
      when 'APPROVE_RECEIPTS'      then p_role in ('owner','manager')
      when 'MANAGE_INVOICES'       then p_role in ('owner','administratie')
      when 'VIEW_DAILY_CLOSING'    then p_role in ('owner','manager','administratie')
      when 'EXECUTE_DAILY_CLOSING' then p_role in ('owner','manager')
      when 'MANAGE_TEAM'           then p_role in ('owner')
      when 'MANAGE_SETTINGS'       then p_role in ('owner','administratie')
      else false
    end, false)
$$;

-- 4. has_perm(): heeft de ingelogde, actieve gebruiker deze permissie?
create or replace function public.has_perm(p_perm text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.role_has_permission(public.my_role(), p_perm)
$$;

-- 5. Rechten: expliciet alles intrekken, daarna alleen authenticated + service_role
revoke all on function public.my_restaurant_id()                     from public, anon, authenticated, service_role;
revoke all on function public.my_role()                              from public, anon, authenticated, service_role;
revoke all on function public.role_has_permission(text, text)        from public, anon, authenticated, service_role;
revoke all on function public.has_perm(text)                         from public, anon, authenticated, service_role;

grant execute on function public.my_restaurant_id()                  to authenticated, service_role;
grant execute on function public.my_role()                           to authenticated, service_role;
grant execute on function public.role_has_permission(text, text)     to authenticated, service_role;
grant execute on function public.has_perm(text)                      to authenticated, service_role;

commit;
