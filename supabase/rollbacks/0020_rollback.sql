-- Rollback van migratie 0020 (stap 6, storage). Zet de drie oorspronkelijke policies terug (migratie 0005).
-- Rol ook de app-code terug (upsert:true) als je de oude update-policy terugzet en overschrijven weer wilt toestaan.
begin;

drop policy if exists "documents bucket read"   on storage.objects;
drop policy if exists "documents bucket upload" on storage.objects;
drop policy if exists "tenant isolation documents bucket read"   on storage.objects;
drop policy if exists "tenant isolation documents bucket upload" on storage.objects;
drop policy if exists "tenant isolation documents bucket update" on storage.objects;

create policy "tenant isolation documents bucket upload"
  on storage.objects for insert
  with check (
    bucket_id = 'documents'
    and (storage.foldername(name))[1]::uuid in (select restaurant_id from users where users.id = auth.uid())
  );
create policy "tenant isolation documents bucket read"
  on storage.objects for select
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1]::uuid in (select restaurant_id from users where users.id = auth.uid())
  );
create policy "tenant isolation documents bucket update"
  on storage.objects for update
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1]::uuid in (select restaurant_id from users where users.id = auth.uid())
  );

commit;
