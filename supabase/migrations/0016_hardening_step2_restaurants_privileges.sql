-- ============================================================
-- Migratie 0016 — SECURITY HARDENING STAP 2: H3 (restaurants) + H8a (TRUNCATE/TRIGGER/REFERENCES weg)
-- Plan: docs/security-hardening-plan.md secties 4 (H3) en 9 (H8a). Vereist migratie 0015 (my_restaurant_id actief-bewust).
--
--  H3  : "tenant isolation restaurants" (for all) vervangen door een SELECT-policy "restaurants read own";
--        INSERT/UPDATE/DELETE op restaurants ingetrokken voor authenticated. De app schrijft nergens naar restaurants
--        (alleen lezen van de naam door ingelogde gebruikers en de service-role ping).
--  H8a : TRUNCATE, TRIGGER, REFERENCES ingetrokken voor anon, authenticated en service_role op alle tabellen in public;
--        anon verliest alle (bestaande) rechten op tabellen en sequences in public; standaardrechten voor nieuwe tabellen: geen TRUNCATE/TRIGGER/REFERENCES meer.
--        DML-rechten van authenticated en service_role (SELECT/INSERT/UPDATE/DELETE) blijven op alle andere tabellen ONGEWIJZIGD.
-- Geen wijziging aan: andere policies, triggers, functies, storage, data. Rollback: supabase/rollbacks/0016_rollback.sql
-- ============================================================
begin;

-- vangnet: stap 1 moet er zijn, en restaurants mag alleen de bekende policy(s) hebben
do $$
declare
  v_other text;
begin
  if to_regprocedure('public.my_restaurant_id()') is null
     or not exists (select 1 from pg_proc where proname = 'my_restaurant_id' and pronamespace = 'public'::regnamespace and proconfig is not null) then
    raise exception 'Stap 1 (migratie 0015) ontbreekt: draai die eerst';
  end if;
  select string_agg(policyname, ', ') into v_other from pg_policies
   where schemaname = 'public' and tablename = 'restaurants'
     and policyname not in ('tenant isolation restaurants', 'restaurants read own');
  if v_other is not null then
    raise exception 'Onverwachte policy op restaurants (%): niet automatisch verwijderd, eerst beoordelen', v_other;
  end if;
end $$;

-- ===== H3: restaurants =====
drop policy if exists "tenant isolation restaurants" on public.restaurants;
drop policy if exists "restaurants read own" on public.restaurants;
create policy "restaurants read own" on public.restaurants
  for select
  using (id = public.my_restaurant_id());

revoke insert, update, delete on public.restaurants from authenticated;

-- ===== H8a: overbodige tabelrechten =====
revoke truncate, trigger, references on all tables in schema public from anon, authenticated, service_role;
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;

alter default privileges in schema public revoke truncate, trigger, references on tables from anon, authenticated, service_role;

commit;
