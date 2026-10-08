-- ============================================================
-- Rollback van migratie 0016 (hardening stap 2): terug naar de stand van vóór stap 2.
--  * policy "tenant isolation restaurants" (for all) terug, "restaurants read own" weg
--  * INSERT/UPDATE/DELETE op restaurants terug voor authenticated
--  * TRUNCATE/TRIGGER/REFERENCES terug voor anon, authenticated en service_role (zoals gemeten in de Fase 0-audit)
--  * standaardrechten voor nieuwe tabellen terug
-- NB: rechten van anon op sequences zijn niet gemeten vóór stap 2; die worden NIET teruggezet (anon heeft geen enkele
--     functie die ze nodig heeft). Veilig om meerdere keren te draaien. Raakt geen data.
-- ============================================================
begin;

drop policy if exists "restaurants read own" on public.restaurants;
drop policy if exists "tenant isolation restaurants" on public.restaurants;
create policy "tenant isolation restaurants" on public.restaurants
  for all
  using (id in (select restaurant_id from public.users where users.id = auth.uid()));

grant insert, update, delete on public.restaurants to authenticated;

grant truncate, trigger, references on all tables in schema public to anon, authenticated, service_role;

alter default privileges in schema public grant truncate, trigger, references on tables to anon, authenticated, service_role;

commit;
