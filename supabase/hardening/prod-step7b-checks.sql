-- ============================================================
-- Plan 7b / migratie 0023 (afgewezen bon niet factureren) — controlequeries voor productie. ALLEEN LEZEN.
-- Draai ze één voor één in de Supabase SQL-editor.
-- 1 = vooraf (voor migratie 0023), 2 = achteraf (na migratie 0023).
-- "Geblokkeerde bon" = een goedkeuring 'rejected' bestaat, geen goedkeuring 'approved', bonstatus niet approved/locked.
-- ============================================================

-- 1. VOORAF
select onderdeel, waarde from (
  select 1 as o, 'trigger open_tabs_guard (verwacht 1, enabled=O)' as onderdeel,
         tgrelid::regclass::text || ' enabled=' || tgenabled::text as waarde
    from pg_trigger where not tgisinternal and tgname = 'open_tabs_guard'
  union all select 2, 'open_tabs_guard bevat de nieuwe controle al (verwacht false)',
         (position('afgewezen bon is nog niet opnieuw goedgekeurd' in pg_get_functiondef('public.open_tabs_guard()'::regprocedure)) > 0)::text
  union all select 2, 'FINGERPRINT open_tabs_guard (toegestaan: 5e61b6f591159e6ad958a35ca3a1ee08 = 0021 uit de repo, of dc970c3a71212b9b27352ae989d437b1 = 0021 zonder de commentaarregel -- UPDATE, zoals in productie gevonden; alles anders: migratie 0023 breekt af)',
         (select md5(btrim(regexp_replace(prosrc, '\s+', ' ', 'g'))) from pg_proc where oid = 'public.open_tabs_guard()'::regprocedure)
  union all select 2, 'eigenschappen open_tabs_guard (verwacht: security_definer=false, config={"search_path=public, pg_temp"}, plpgsql, trigger, v)',
         (select 'security_definer=' || p.prosecdef::text || ', config=' || coalesce(p.proconfig::text, '-') || ', ' || l.lanname || ', ' || p.prorettype::regtype::text || ', ' || p.provolatile::text
            from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = 'public.open_tabs_guard()'::regprocedure)
  union all select 2, 'trigger-definitie (verwacht: BEFORE INSERT OR DELETE OR UPDATE ON public.open_tabs FOR EACH ROW EXECUTE FUNCTION open_tabs_guard())',
         (select pg_get_triggerdef(oid) from pg_trigger where not tgisinternal and tgname = 'open_tabs_guard' limit 1)
  union all select 2, 'rechten: authenticated,service_role,anon kunnen open_tabs_guard() uitvoeren (verwacht false,false,false)',
         has_function_privilege('authenticated', 'public.open_tabs_guard()', 'EXECUTE')::text || ','
         || has_function_privilege('service_role', 'public.open_tabs_guard()', 'EXECUTE')::text || ','
         || has_function_privilege('anon', 'public.open_tabs_guard()', 'EXECUTE')::text
  union all select 2, 'andere grantees dan de eigenaar met EXECUTE (verwacht: (leeg); anders breekt migratie 0023 af)',
         coalesce((select string_agg(case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end, ',')
                     from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                    where p.oid = 'public.open_tabs_guard()'::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner), '(leeg)')
  union all select 2, 'ruwe ACL en eigenaar van open_tabs_guard() (informatief)',
         (select coalesce(p.proacl::text, '(NULL = standaard)') || ' / eigenaar ' || p.proowner::regrole::text from pg_proc p where p.oid = 'public.open_tabs_guard()'::regprocedure)
  union all select 3, 'migratie 0022 aanwezig (verwacht true)',
         (position('niet meer worden afgewezen of verlopen' in pg_get_functiondef('public.approvals_guard()'::regprocedure)) > 0)::text
  union all select 4, 'rekeningen', status || ': ' || count(*) from public.open_tabs group by status
  union all select 5, 'bonnen', status || ': ' || count(*) from public.receipts group by status
  union all select 6, 'goedkeuringen', status || ': ' || count(*) from public.approvals group by status
  union all select 7, 'GESLOTEN rekeningen met een geblokkeerde bon (na 0023 niet te factureren tot opgelost; informatief)',
         count(distinct t.id)::text
    from public.open_tabs t join public.receipts r on r.open_tab_id = t.id
   where t.status = 'closed' and r.status not in ('approved', 'locked')
     and exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'rejected')
     and not exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'approved')
  union all select 8, 'OPEN rekeningen met een geblokkeerde bon (informatief)',
         count(distinct t.id)::text
    from public.open_tabs t join public.receipts r on r.open_tab_id = t.id
   where t.status = 'open' and r.status not in ('approved', 'locked')
     and exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'rejected')
     and not exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'approved')
  union all select 9, 'GEFACTUREERDE rekeningen met een geblokkeerde bon (historisch, wordt niet aangeraakt; informatief)',
         count(distinct t.id)::text
    from public.open_tabs t join public.receipts r on r.open_tab_id = t.id
   where t.status = 'invoiced' and r.status not in ('approved', 'locked')
     and exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'rejected')
     and not exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'approved')
  union all select 10, 'bonnen totaal', count(*)::text from public.receipts
) x order by o, waarde;

-- 2. ACHTERAF
select onderdeel, waarde from (
  select 1 as o, 'trigger open_tabs_guard (verwacht 1, enabled=O)' as onderdeel,
         tgrelid::regclass::text || ' enabled=' || tgenabled::text as waarde
    from pg_trigger where not tgisinternal and tgname = 'open_tabs_guard'
  union all select 2, 'open_tabs_guard bevat de nieuwe controle (verwacht true)',
         (position('afgewezen bon is nog niet opnieuw goedgekeurd' in pg_get_functiondef('public.open_tabs_guard()'::regprocedure)) > 0)::text
  union all select 2, 'FINGERPRINT open_tabs_guard (verwacht fb9257a37816d3de6775d982135110b2 = 0023 met commentaar; 4e5b902991d05e76167ae7581c382636 = 0023 zonder commentaar is ook goed)',
         (select md5(btrim(regexp_replace(prosrc, '\s+', ' ', 'g'))) from pg_proc where oid = 'public.open_tabs_guard()'::regprocedure)
  union all select 3, 'functie niet rechtstreeks uitvoerbaar (verwacht false,false,false)',
         has_function_privilege('authenticated', 'public.open_tabs_guard()', 'EXECUTE')::text || ','
         || has_function_privilege('service_role', 'public.open_tabs_guard()', 'EXECUTE')::text || ','
         || has_function_privilege('anon', 'public.open_tabs_guard()', 'EXECUTE')::text
  union all select 3, 'andere grantees dan de eigenaar met EXECUTE (verwacht: leeg; anders breekt de migratie af)',
         coalesce((select string_agg(case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end, ',')
                     from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                    where p.oid = 'public.open_tabs_guard()'::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner), '(leeg)')
  union all select 4, 'alle vier de guard-triggers actief (verwacht 4)', count(*)::text
    from pg_trigger where not tgisinternal and tgenabled = 'O' and tgname in ('receipts_guard', 'receipt_lines_guard', 'open_tabs_guard', 'approvals_guard')
  union all select 5, 'aantal policies op de vier tabellen (verwacht 13)', count(*)::text
    from pg_policies where schemaname = 'public' and tablename in ('open_tabs', 'receipts', 'receipt_lines', 'approvals')
  union all select 6, 'rekeningen', status || ': ' || count(*) from public.open_tabs group by status
  union all select 7, 'bonnen', status || ': ' || count(*) from public.receipts group by status
  union all select 8, 'goedkeuringen', status || ': ' || count(*) from public.approvals group by status
  union all select 9, 'bonnen totaal', count(*)::text from public.receipts
) x order by o, waarde;
