-- ============================================================
-- Migratie 0009: RLS-recursie herstellen (kritieke bugfix uit migratie 0008)
-- Zie docs/architecture.md v1.24a voor de volledige diagnose.
-- ============================================================

create or replace function my_restaurant_id()
returns uuid
language sql
security definer
stable
as $$
  select restaurant_id from users where id = auth.uid()
$$;

drop policy if exists "users can see team members" on users;
create policy "users can see team members" on users
  for select using (
    restaurant_id = my_restaurant_id()
  );
