-- ============================================================
-- Migratie 0018 — SECURITY HARDENING STAP 4: H5a (logboeken append-only)
-- Tabellen: activity_log, audit_log, domain_events. Vereist 0015 (helpers). Geen app-wijziging nodig.
--
--  * Gewone gebruikers (authenticated) kunnen logregels alleen nog LEZEN (eigen restaurant) en TOEVOEGEN
--    (eigen restaurant, onder eigen naam: user_id / changed_by / published_by = auth.uid()). UPDATE en DELETE zijn ingetrokken.
--  * Append-only vangnet in de database (trigger): UPDATE, DELETE en TRUNCATE zijn voor IEDEREEN geweigerd, ook voor service-role
--    en postgres. Er is GEEN algemene service-role-uitzondering. De enige smalle uitzondering: een DELETE van logregels
--    van een restaurant dat zelf al verwijderd is (ON DELETE CASCADE bij het verwijderen van het hele restaurant).
--  * Service-role behoudt INSERT/SELECT zoals nu (publieke goedkeuring schrijft met user_id/published_by = NULL).
--    Service-role DML-rechten worden niet verlaagd (inventaris in stap 11); de trigger beschermt de data.
--  * Bestaande logdata blijft ongewijzigd. H5b (alle logs via server) is een latere keuze en hier NIET gedaan.
-- Rollback: supabase/rollbacks/0018_rollback.sql
-- ============================================================
begin;

do $$
begin
  if to_regprocedure('public.my_restaurant_id()') is null then
    raise exception 'Stap 1 (migratie 0015) ontbreekt: draai die eerst';
  end if;
  if exists (select 1 from pg_policies
             where schemaname = 'public' and tablename in ('activity_log', 'audit_log', 'domain_events')
               and policyname not in ('tenant isolation activity_log', 'tenant isolation audit_log', 'tenant isolation domain_events',
                                      'activity_log read own restaurant', 'activity_log insert own',
                                      'audit_log read own restaurant', 'audit_log insert own',
                                      'domain_events read own restaurant', 'domain_events insert own')) then
    raise exception 'Onverwachte policy op een logtabel: eerst beoordelen';
  end if;
end $$;

-- 1. Policies: "for all" vervangen door lezen + toevoegen (eigen restaurant, eigen naam)
drop policy if exists "tenant isolation activity_log" on public.activity_log;
drop policy if exists "activity_log read own restaurant" on public.activity_log;
drop policy if exists "activity_log insert own" on public.activity_log;
create policy "activity_log read own restaurant" on public.activity_log
  for select to authenticated using (restaurant_id = public.my_restaurant_id());
create policy "activity_log insert own" on public.activity_log
  for insert to authenticated
  with check (restaurant_id = public.my_restaurant_id() and user_id = auth.uid());

drop policy if exists "tenant isolation audit_log" on public.audit_log;
drop policy if exists "audit_log read own restaurant" on public.audit_log;
drop policy if exists "audit_log insert own" on public.audit_log;
create policy "audit_log read own restaurant" on public.audit_log
  for select to authenticated using (restaurant_id = public.my_restaurant_id());
create policy "audit_log insert own" on public.audit_log
  for insert to authenticated
  with check (restaurant_id = public.my_restaurant_id() and changed_by = auth.uid());

drop policy if exists "tenant isolation domain_events" on public.domain_events;
drop policy if exists "domain_events read own restaurant" on public.domain_events;
drop policy if exists "domain_events insert own" on public.domain_events;
create policy "domain_events read own restaurant" on public.domain_events
  for select to authenticated using (restaurant_id = public.my_restaurant_id());
create policy "domain_events insert own" on public.domain_events
  for insert to authenticated
  with check (restaurant_id = public.my_restaurant_id() and published_by = auth.uid());

-- 2. Rechten: gewone gebruikers kunnen logregels niet meer wijzigen of verwijderen
revoke update, delete on public.activity_log, public.audit_log, public.domain_events from authenticated;

-- 3. Append-only vangnet (voor iedereen, ook service-role en postgres)
create or replace function public.logs_append_only()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Enige uitzondering: het hele restaurant is verwijderd en de database ruimt de logregels mee op (cascade).
  if tg_op = 'DELETE' and not exists (select 1 from public.restaurants r where r.id = old.restaurant_id) then
    return old;
  end if;
  raise exception 'Logboek % is append-only: % is niet toegestaan', tg_table_name, tg_op
    using errcode = 'insufficient_privilege';
end
$$;

create or replace function public.logs_no_truncate()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception 'Logboek % is append-only: TRUNCATE is niet toegestaan', tg_table_name
    using errcode = 'insufficient_privilege';
end
$$;

drop trigger if exists logs_append_only on public.activity_log;
create trigger logs_append_only before update or delete on public.activity_log
  for each row execute function public.logs_append_only();
drop trigger if exists logs_no_truncate on public.activity_log;
create trigger logs_no_truncate before truncate on public.activity_log
  for each statement execute function public.logs_no_truncate();

drop trigger if exists logs_append_only on public.audit_log;
create trigger logs_append_only before update or delete on public.audit_log
  for each row execute function public.logs_append_only();
drop trigger if exists logs_no_truncate on public.audit_log;
create trigger logs_no_truncate before truncate on public.audit_log
  for each statement execute function public.logs_no_truncate();

drop trigger if exists logs_append_only on public.domain_events;
create trigger logs_append_only before update or delete on public.domain_events
  for each row execute function public.logs_append_only();
drop trigger if exists logs_no_truncate on public.domain_events;
create trigger logs_no_truncate before truncate on public.domain_events
  for each statement execute function public.logs_no_truncate();

revoke all on function public.logs_append_only() from public, anon, authenticated, service_role;
revoke all on function public.logs_no_truncate() from public, anon, authenticated, service_role;

commit;
