-- ============================================================
-- Migratie 0013: ontbrekende UPDATE/DELETE-policies op 'users'
-- Zie docs/architecture.md v1.40 voor de volledige diagnose.
--
-- Oorzaak: 'users' had sinds het begin alleen SELECT-policies (v1.4,
-- v1.24a). Rol wijzigen/deactiveren/verwijderen deed nooit een echte
-- UPDATE/DELETE-poging tot deze test — RLS blokkeerde dit stilzwijgend
-- (0 rijen geraakt), wat PostgREST vertaalt naar "Cannot coerce the
-- result to a single JSON object" bij een .single()-call.
-- ============================================================

create policy "team managers can update team members" on users
  for update using (
    restaurant_id = my_restaurant_id()
  )
  with check (
    restaurant_id = my_restaurant_id()
  );

create policy "team managers can delete team members" on users
  for delete using (
    restaurant_id = my_restaurant_id()
  );
