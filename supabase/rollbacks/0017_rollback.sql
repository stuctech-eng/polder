-- ============================================================
-- Rollback van migratie 0017 (hardening stap 3): terug naar de stand van vóór stap 3.
-- LET OP: draai dit ALLEEN samen met het terugzetten van de app-code (vorige release), anders schrijft de oude
-- code via de gebruikersverbinding en dat werkt weer — met alle oude risico's (zelf owner worden, collega's verwijderen).
-- Veilig om meerdere keren te draaien. Raakt geen data.
-- ============================================================
begin;

drop trigger if exists users_keep_owner on public.users;
drop trigger if exists users_guard on public.users;
drop function if exists public.users_keep_owner();
drop function if exists public.users_guard();

grant insert, update, delete on public.users to authenticated;

drop policy if exists "team managers can update team members" on public.users;
create policy "team managers can update team members" on public.users
  for update
  using (restaurant_id = my_restaurant_id())
  with check (restaurant_id = my_restaurant_id());

drop policy if exists "team managers can delete team members" on public.users;
create policy "team managers can delete team members" on public.users
  for delete
  using (restaurant_id = my_restaurant_id());

commit;
