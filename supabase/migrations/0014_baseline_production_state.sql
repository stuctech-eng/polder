-- ============================================================
-- Migratie 0014: BASELINE — legt de daadwerkelijke productietoestand vast
-- Zie docs/architecture.md sectie 13 (Fase 0 — schema- en securityaudit).
--
-- DOEL: een nieuwe omgeving die uitsluitend uit de migraties wordt opgebouwd,
-- moet dezelfde uitgangssituatie hebben als productie.
--
-- GEEN gedragswijziging. GEEN security-hardening. Volledig idempotent:
-- in productie is deze migratie een no-op (alles bestaat daar al exact zo,
-- vastgesteld op 2026-10-08 met pg_class / pg_policies / pg_proc).
--
-- Gevonden verschil repo vs productie:
--   * RLS op 'users' stond in productie AAN (handmatig gedaan, o.a. blijkend
--     uit de recursiefout van v1.24), maar stond in geen enkele migratie.
--     Een nieuwe omgeving had 'users' dus ZONDER RLS gekregen, terwijl de
--     vier policies daar wel bestonden (zonder RLS doen policies niets).
--
-- Bewust NIET opgenomen (zie architecture.md sectie 13):
--   * email_settings (0002): staat niet in productie en wordt in de code niet
--     gebruikt. Niet aan productie toevoegen zonder functionele reden.
--   * Hardening van te ruime rechten (rolbewuste policies, append-only logs,
--     TRUNCATE/TRIGGER/REFERENCES intrekken, search_path van
--     my_restaurant_id): aparte stap, alleen na expliciete GO.
-- ============================================================

-- 1. RLS op users (productie: aan)
alter table users enable row level security;

-- 2. my_restaurant_id(): identiek aan productie (SECURITY DEFINER, stable,
--    geen vast search_path — dat laatste is een hardening-punt, hier bewust niet gewijzigd)
create or replace function my_restaurant_id()
returns uuid
language sql
security definer
stable
as $$
  select restaurant_id from users where id = auth.uid()
$$;

-- 3. De vier policies op users zoals die in productie bestaan.
--    Alleen aanmaken als ze ontbreken (nooit bestaande vervangen of verwijderen).
--    Let op: er is bewust GEEN INSERT-policy op users (profielaanmaak gaat
--    straks server-side; zie architecture.md sectie 13, "nog onbewezen").
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'users'
      and policyname = 'users can see own profile'
  ) then
    create policy "users can see own profile" on users
      for select using (id = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'users'
      and policyname = 'users can see team members'
  ) then
    create policy "users can see team members" on users
      for select using (restaurant_id = my_restaurant_id());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'users'
      and policyname = 'team managers can update team members'
  ) then
    create policy "team managers can update team members" on users
      for update using (restaurant_id = my_restaurant_id())
      with check (restaurant_id = my_restaurant_id());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'users'
      and policyname = 'team managers can delete team members'
  ) then
    create policy "team managers can delete team members" on users
      for delete using (restaurant_id = my_restaurant_id());
  end if;
end
$$;
