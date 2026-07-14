-- ============================================================
-- Migratie 0008: Fase A.5 — Teambeheer / User Management
-- ============================================================

alter table users add column if not exists is_active boolean not null default true;

-- Teamleden van hetzelfde restaurant mogen elkaar zien (nooit een ander restaurant).
-- Aanvullend op de bestaande "users can see own profile"-policy (v1.4), niet vervangend.
drop policy if exists "users can see team members" on users;
create policy "users can see team members" on users
  for select using (
    restaurant_id in (
      select u.restaurant_id from users u where u.id = auth.uid()
    )
  );
