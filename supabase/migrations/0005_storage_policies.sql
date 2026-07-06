-- ============================================================
-- Migratie 0005: Storage-policies voor de 'documents' bucket
-- Oorzaak: storage.objects heeft een eigen RLS-systeem, los van de
-- publieke tabellen. Bucket aanmaken alleen is niet genoeg — net als
-- bij v1.4/v1.5 moet er een expliciete policy bij.
--
-- Pad-structuur: {restaurant_id}/invoices/{invoice_id}.pdf
-- We staan toe op basis van de eerste mapnaam (restaurant_id).
-- ============================================================

drop policy if exists "tenant isolation documents bucket upload" on storage.objects;
create policy "tenant isolation documents bucket upload"
  on storage.objects for insert
  with check (
    bucket_id = 'documents'
    and (storage.foldername(name))[1]::uuid in (
      select restaurant_id from users where users.id = auth.uid()
    )
  );

drop policy if exists "tenant isolation documents bucket read" on storage.objects;
create policy "tenant isolation documents bucket read"
  on storage.objects for select
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1]::uuid in (
      select restaurant_id from users where users.id = auth.uid()
    )
  );

drop policy if exists "tenant isolation documents bucket update" on storage.objects;
create policy "tenant isolation documents bucket update"
  on storage.objects for update
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1]::uuid in (
      select restaurant_id from users where users.id = auth.uid()
    )
  );
