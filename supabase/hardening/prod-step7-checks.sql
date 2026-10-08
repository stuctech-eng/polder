-- ============================================================
-- Stap 7 (H4a) — controlequeries voor productie. ALLEEN LEZEN. Draai ze één voor één in de Supabase SQL-editor.
-- 1 = vooraf (voor migratie 0021), 2 = achteraf (na migratie 0021).
-- ============================================================

-- 1. VOORAF
select onderdeel, waarde from (
  select 1 as o, 'policy' as onderdeel, tablename || ' / ' || policyname || ' (' || cmd || ')' as waarde
    from pg_policies where schemaname = 'public' and tablename in ('open_tabs', 'receipts', 'receipt_lines', 'approvals')
  union all select 2, 'trigger', tgrelid::regclass::text || ' / ' || tgname
    from pg_trigger where not tgisinternal and tgrelid in ('public.open_tabs'::regclass, 'public.receipts'::regclass, 'public.receipt_lines'::regclass, 'public.approvals'::regclass)
  union all select 3, 'helpers aanwezig', (to_regprocedure('public.has_perm(text)') is not null and to_regprocedure('public.my_restaurant_id()') is not null)::text
  union all select 4, 'rekeningen', status || ': ' || count(*) from public.open_tabs group by status
  union all select 5, 'bonnen', status || ': ' || count(*) from public.receipts group by status
  union all select 6, 'goedkeuringen', status || ': ' || count(*) from public.approvals group by status
  union all select 7, 'bonregels', count(*)::text from public.receipt_lines
  union all select 8, 'bon in wacht zonder open goedkeuring', count(*)::text from public.receipts r
    where r.status = 'pending_approval' and not exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'pending')
  union all select 9, 'open goedkeuring bij bon die niet in wacht staat', count(*)::text from public.approvals a
    join public.receipts r on r.id = a.receipt_id where a.status = 'pending' and r.status <> 'pending_approval'
  union all select 10, 'bon (niet locked/approved) op gefactureerde rekening', count(*)::text from public.receipts r
    join public.open_tabs t on t.id = r.open_tab_id where t.status = 'invoiced' and r.status not in ('locked', 'approved')
  union all select 11, 'bon op niet-open rekening met status draft/linked', count(*)::text from public.receipts r
    join public.open_tabs t on t.id = r.open_tab_id where t.status <> 'open' and r.status in ('draft', 'linked')
) x order by o, waarde;

-- 2. ACHTERAF
select onderdeel, waarde from (
  select 1 as o, 'policy' as onderdeel, tablename || ' / ' || policyname || ' (' || cmd || ') ' || roles::text as waarde
    from pg_policies where schemaname = 'public' and tablename in ('open_tabs', 'receipts', 'receipt_lines', 'approvals')
  union all select 2, 'trigger', tgrelid::regclass::text || ' / ' || tgname || ' enabled=' || tgenabled::text
    from pg_trigger where not tgisinternal and tgname in ('receipts_guard', 'receipt_lines_guard', 'open_tabs_guard', 'approvals_guard')
  union all select 3, 'aantal policies (verwacht 13)', count(*)::text from pg_policies where schemaname = 'public' and tablename in ('open_tabs', 'receipts', 'receipt_lines', 'approvals')
  union all select 4, 'rekeningen', status || ': ' || count(*) from public.open_tabs group by status
  union all select 5, 'bonnen', status || ': ' || count(*) from public.receipts group by status
  union all select 6, 'goedkeuringen', status || ': ' || count(*) from public.approvals group by status
  union all select 7, 'bonregels', count(*)::text from public.receipt_lines
) x order by o, waarde;
