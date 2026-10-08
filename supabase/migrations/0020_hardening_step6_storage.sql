-- ============================================================
-- Migratie 0020 — SECURITY HARDENING STAP 6: H6 (storage, bucket 'documents')
-- Plan: docs/security-hardening-plan.md sectie 7. Vereist 0015 (helpers).
-- VOLGORDE: eerst de app-code deployen (upload met upsert:false; werkt met oude én nieuwe policies), DAARNA deze migratie.
--
--  * Pad-structuur ongewijzigd: {restaurant_id}/invoices/{invoice_id}.pdf. Bestaande bestanden blijven leesbaar.
--  * LEZEN en UPLOADEN: alleen in de eigen restaurant-map (eerste padonderdeel = my_restaurant_id()) én met recht
--    MANAGE_INVOICES (owner, administratie) — gelijk aan wat de routes al afdwingen. Gedeactiveerde gebruikers vallen af
--    (helpers uit stap 1). Een pad dat niet met een uuid begint geeft nu een nette weigering i.p.v. een cast-fout.
--  * UPDATE (overschrijven) en DELETE: geen policy → voor gewone gebruikers geweigerd; bestanden zijn onveranderlijk.
--  * De rechten op het storage-schema zelf (beheerd door Supabase) worden NIET aangepast; alleen policies.
--  * Bewust niet gedaan: service-role (server-side, omzeilt RLS) kan nog schrijven/verwijderen — de app gebruikt dat niet voor
--    storage; een trigger op een door Supabase beheerde tabel is hier niet gewenst (zie docs/architecture.md 13.14).
-- Rollback: supabase/rollbacks/0020_rollback.sql
-- ============================================================
begin;

do $$
begin
  if to_regprocedure('public.has_perm(text)') is null or to_regprocedure('public.my_restaurant_id()') is null then
    raise exception 'Stap 1 (migratie 0015) ontbreekt: draai die eerst';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
             and policyname not in ('tenant isolation documents bucket upload', 'tenant isolation documents bucket read',
                                    'tenant isolation documents bucket update',
                                    'documents bucket read', 'documents bucket upload')) then
    raise exception 'Onverwachte policy op storage.objects: eerst beoordelen';
  end if;
end $$;

drop policy if exists "tenant isolation documents bucket read"   on storage.objects;
drop policy if exists "tenant isolation documents bucket upload" on storage.objects;
drop policy if exists "tenant isolation documents bucket update" on storage.objects;
drop policy if exists "documents bucket read"   on storage.objects;
drop policy if exists "documents bucket upload" on storage.objects;

create policy "documents bucket read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.my_restaurant_id()::text
    and public.has_perm('MANAGE_INVOICES')
  );

create policy "documents bucket upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.my_restaurant_id()::text
    and public.has_perm('MANAGE_INVOICES')
  );

-- bewust GEEN update- en GEEN delete-policy: bestanden in de bucket zijn voor gebruikers onveranderlijk

commit;
