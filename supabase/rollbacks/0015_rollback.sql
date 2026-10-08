-- ============================================================
-- Rollback van migratie 0015 (hardening stap 1): terug naar de productiestand van vóór stap 1
-- (my_restaurant_id zonder search_path en zonder is_active, PUBLIC-execute; nieuwe helpers weg).
-- Veilig om meerdere keren te draaien. Raakt geen policies, tabellen of data.
-- ============================================================
begin;

create or replace function public.my_restaurant_id()
returns uuid
language sql
stable
security definer
as $$
  select restaurant_id from users where id = auth.uid()
$$;

revoke all on function public.my_restaurant_id() from public, anon, authenticated, service_role;
grant execute on function public.my_restaurant_id() to public;   -- zoals vóór stap 1: alleen PUBLIC (+ eigenaar)

drop function if exists public.has_perm(text);
drop function if exists public.role_has_permission(text, text);
drop function if exists public.my_role();

commit;
