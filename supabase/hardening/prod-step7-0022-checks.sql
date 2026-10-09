-- ============================================================
-- Migratie 0022 (aanscherping approvals_guard) — controlequeries voor productie. ALLEEN LEZEN.
-- Draai ze één voor één in de Supabase SQL-editor.
-- 1 = vooraf (voor migratie 0022), 2 = achteraf (na migratie 0022).
-- ============================================================

-- 1. VOORAF
select onderdeel, waarde from (
  select 1 as o, 'trigger approvals_guard (verwacht 1, enabled=O)' as onderdeel,
         tgrelid::regclass::text || ' enabled=' || tgenabled::text as waarde
    from pg_trigger where not tgisinternal and tgname = 'approvals_guard'
  union all select 2, 'functie bevat al de nieuwe controles (verwacht false)',
         (position('niet meer worden afgewezen of verlopen' in pg_get_functiondef('public.approvals_guard()'::regprocedure)) > 0)::text
  union all select 3, 'bonnen', status || ': ' || count(*) from public.receipts group by status
  union all select 4, 'goedkeuringen', status || ': ' || count(*) from public.approvals group by status
  union all select 5, 'afgehandelde bon (approved/locked) met afwijzing/verlopen maar zonder goedkeuring (verwacht 0)',
         count(*)::text from public.receipts r
    where r.status in ('approved', 'locked')
      and exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status in ('rejected', 'expired'))
      and not exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'approved')
  union all select 6, 'afgehandelde bon (approved/locked) met nog openstaande goedkeuring (informatief; blijft alleen naar approved mogelijk)',
         count(*)::text from public.receipts r
    where r.status in ('approved', 'locked') and exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'pending')
  union all select 7, 'bon met meer dan een openstaande goedkeuring (informatief)',
         count(*)::text from (select receipt_id from public.approvals where status = 'pending' group by receipt_id having count(*) > 1) d
  union all select 8, 'bonnen totaal', count(*)::text from public.receipts
) x order by o, waarde;

-- 2. ACHTERAF
select onderdeel, waarde from (
  select 1 as o, 'trigger approvals_guard (verwacht 1, enabled=O)' as onderdeel,
         tgrelid::regclass::text || ' enabled=' || tgenabled::text as waarde
    from pg_trigger where not tgisinternal and tgname = 'approvals_guard'
  union all select 2, 'functie bevat de INSERT-controle (verwacht true)',
         (position('geen nieuwe goedkeuring meer krijgen' in pg_get_functiondef('public.approvals_guard()'::regprocedure)) > 0)::text
  union all select 3, 'functie bevat de UPDATE-controle (verwacht true)',
         (position('niet meer worden afgewezen of verlopen' in pg_get_functiondef('public.approvals_guard()'::regprocedure)) > 0)::text
  union all select 4, 'functie niet rechtstreeks uitvoerbaar (verwacht false,false,false)',
         has_function_privilege('authenticated', 'public.approvals_guard()', 'EXECUTE')::text || ','
         || has_function_privilege('service_role', 'public.approvals_guard()', 'EXECUTE')::text || ','
         || has_function_privilege('anon', 'public.approvals_guard()', 'EXECUTE')::text
  union all select 5, 'aantal policies op de vier tabellen (verwacht 13)', count(*)::text
    from pg_policies where schemaname = 'public' and tablename in ('open_tabs', 'receipts', 'receipt_lines', 'approvals')
  union all select 6, 'bonnen', status || ': ' || count(*) from public.receipts group by status
  union all select 7, 'goedkeuringen', status || ': ' || count(*) from public.approvals group by status
  union all select 8, 'bonnen totaal', count(*)::text from public.receipts
) x order by o, waarde;
