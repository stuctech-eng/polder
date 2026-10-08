-- ============================================================
-- Migratie 0017 — SECURITY HARDENING STAP 3: H2 (users) — database-deel
-- Plan: docs/security-hardening-plan.md sectie 3. Vereist 0015 (helpers) en 0016.
-- VOLGORDE: eerst de app-code deployen (die werkt met de oude én de nieuwe database), DAARNA deze migratie draaien.
--
--  * Policies "team managers can update/delete team members" vervallen; INSERT/UPDATE/DELETE op users ingetrokken voor
--    authenticated. Profielen worden alleen nog server-side aangemaakt/gewijzigd/verwijderd (service-role, na requireRole).
--  * SELECT-policies op users blijven ONGEWIJZIGD ("own profile" + "see team members", gebruikt my_restaurant_id()):
--    besluit D2 (alleen de owner ziet het team) is nog open; het dashboard en de dagafsluiting tonen namen van collega's.
--  * DB-vangnet users_guard (BEFORE UPDATE): id en restaurant_id onveranderlijk — voor iedereen, ook service-role.
--  * DB-vangnet users_keep_owner (constraint trigger, deferred): een restaurant houdt altijd minstens één ACTIEVE owner,
--    voor iedereen (ook service-role). Geen uitzondering behalve het verwijderen van het hele restaurant (cascade).
-- Rollback: supabase/rollbacks/0017_rollback.sql
-- ============================================================
begin;

do $$
begin
  if to_regprocedure('public.has_perm(text)') is null then
    raise exception 'Stap 1 (migratie 0015) ontbreekt: draai die eerst';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'users'
             and policyname not in ('users can see own profile', 'users can see team members',
                                    'team managers can update team members', 'team managers can delete team members')) then
    raise exception 'Onverwachte policy op users: eerst beoordelen';
  end if;
end $$;

-- 1. Policies voor wijzigen/verwijderen weg; schrijfrechten weg
drop policy if exists "team managers can update team members" on public.users;
drop policy if exists "team managers can delete team members" on public.users;
revoke insert, update, delete on public.users from authenticated;

-- 2. id en restaurant_id zijn onveranderlijk (ook voor service-role)
create or replace function public.users_guard()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'users.id is onveranderlijk' using errcode = 'check_violation';
  end if;
  if new.restaurant_id is distinct from old.restaurant_id then
    raise exception 'users.restaurant_id is onveranderlijk' using errcode = 'check_violation';
  end if;
  return new;
end
$$;

drop trigger if exists users_guard on public.users;
create trigger users_guard
  before update on public.users
  for each row execute function public.users_guard();

-- 3. Laatste actieve owner: controle aan het einde van de transactie (deferred), voor iedereen
create or replace function public.users_keep_owner()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_locked integer;
begin
  -- alleen relevant als een ACTIEVE owner verdwijnt, gedeactiveerd of gedegradeerd wordt
  if old.role = 'owner' and old.is_active
     and (tg_op = 'DELETE' or new.role <> 'owner' or not new.is_active) then
    -- serialiseer gelijktijdige owner-wijzigingen in hetzelfde restaurant (conflicteert niet met FK-checks)
    select 1 into v_locked from public.restaurants r where r.id = old.restaurant_id for no key update;
    -- restaurant zelf verwijderd (cascade)? dan is er niets meer te bewaken
    if v_locked is not null
       and not exists (select 1 from public.users u
                       where u.restaurant_id = old.restaurant_id and u.role = 'owner' and u.is_active) then
      raise exception 'Een restaurant moet minstens één actieve eigenaar houden'
        using errcode = 'check_violation';
    end if;
  end if;
  return null;
end
$$;

drop trigger if exists users_keep_owner on public.users;
create constraint trigger users_keep_owner
  after update or delete on public.users
  deferrable initially deferred
  for each row execute function public.users_keep_owner();

revoke all on function public.users_guard()      from public, anon, authenticated, service_role;
revoke all on function public.users_keep_owner() from public, anon, authenticated, service_role;

commit;
