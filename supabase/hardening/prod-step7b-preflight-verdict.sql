-- Plan 7b — read-only productiepreflight (spiegelt de preflight van migratie 0023). ALLEEN LEZEN, wijzigt niets.
-- Elke rij geeft PASS of FAIL. Alle rijen moeten PASS zijn; bij één FAIL: stoppen.
with f as (
  select p.oid, p.proacl, p.proowner, p.prosecdef, p.proconfig, p.provolatile,
         md5(btrim(regexp_replace(p.prosrc, '\s+', ' ', 'g'))) as fp,
         l.lanname, p.prorettype::regtype::text as ret
    from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = to_regprocedure('public.open_tabs_guard()')
), t as (
  select count(*) as n, bool_and(tgrelid = to_regclass('public.open_tabs')) as rel_ok, bool_and(tgfoid = to_regprocedure('public.open_tabs_guard()')) as fn_ok, max(tgrelid::regclass::text) as rel, max(tgfoid::regprocedure::text) as fn, max(tgtype) as ty, max(tgenabled::text) as en, max(tgnargs) as na,
         bool_or(tgqual is not null) as has_when, bool_or(tgattr::text <> '') as has_cols, max(tgconstraint::text) as cons,
         (select count(*) from pg_trigger x where not x.tgisinternal and x.tgfoid = to_regprocedure('public.open_tabs_guard()')) as fn_trigs
    from pg_trigger where not tgisinternal and tgname = 'open_tabs_guard'
), a as (
  select md5(btrim(regexp_replace(p.prosrc, '\s+', ' ', 'g'))) as fp, p.prosecdef, p.proconfig, l.lanname, p.prorettype::regtype::text as ret, p.provolatile, p.proacl, p.proowner
    from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = to_regprocedure('public.approvals_guard()')
)
select 1 as nr, 'functie bestaat' as controle,
       case when exists (select 1 from f) then 'PASS' else 'FAIL' end as uitkomst, '' as waarde
union all select 2, 'fingerprint is een toegestane versie (5e61…=0021 repo, dc97…=0021 zonder commentaar = productie, fb92…=0023, 4e5b…=0023 zonder commentaar)',
       case when (select fp from f) in ('5e61b6f591159e6ad958a35ca3a1ee08','dc970c3a71212b9b27352ae989d437b1','fb9257a37816d3de6775d982135110b2','4e5b902991d05e76167ae7581c382636') then 'PASS' else 'FAIL' end,
       coalesce((select fp from f), '-')
union all select 3, 'eigenschappen: invoker, search_path=public, pg_temp, plpgsql, trigger, volatile',
       case when (select prosecdef = false and proconfig = array['search_path=public, pg_temp'] and lanname = 'plpgsql' and ret = 'trigger' and provolatile = 'v' from f) then 'PASS' else 'FAIL' end, ''
union all select 4, 'ACL: geen andere grantee dan de eigenaar (PUBLIC meegeteld)',
       case when not exists (select 1 from f cross join lateral aclexplode(coalesce(f.proacl, acldefault('f', f.proowner))) a
                              where a.privilege_type = 'EXECUTE' and a.grantee <> f.proowner) then 'PASS' else 'FAIL' end,
       coalesce((select proacl::text from f), '(NULL)')
union all select 5, 'effectief: anon/authenticated/service_role kunnen de functie niet uitvoeren',
       case when not exists (select 1 from pg_roles r where r.rolname in ('anon','authenticated','service_role')
                                and has_function_privilege(r.oid, to_regprocedure('public.open_tabs_guard()'), 'EXECUTE')) then 'PASS' else 'FAIL' end, ''
union all select 6, 'trigger via catalogus: precies één, op public.open_tabs, roept open_tabs_guard() aan, BEFORE ROW INSERT/UPDATE/DELETE (31), enabled O, geen argumenten/WHEN/kolomlijst, geen andere trigger op de functie',
       case when (select n = 1 and rel_ok and fn_ok and ty = 31 and en = 'O' and na = 0 and not has_when and not has_cols and cons = '0' and fn_trigs = 1 from t) then 'PASS' else 'FAIL' end,
       (select coalesce(rel,'-') || ' / ' || coalesce(fn,'-') || ' / type ' || coalesce(ty::text,'-') || ' / ' || coalesce(en,'-') || ' / functie-triggers ' || fn_trigs from t)
union all select 7, 'migratie 0022: approvals_guard() is een toegestane versie (3320…=bestand, d84e5483…=zonder commentaar = productie)',
       case when (select fp from a) in ('3320a9525bbc54bdd29516a459fc6a61','d84e5483f3bad1bcb48aa443a2e16644') then 'PASS' else 'FAIL' end, coalesce((select fp from a), '-')
union all select 8, 'approvals_guard(): invoker, search_path=public, pg_temp, plpgsql, trigger, volatile',
       case when (select prosecdef = false and proconfig = array['search_path=public, pg_temp'] and lanname = 'plpgsql' and ret = 'trigger' and provolatile = 'v' from a) then 'PASS' else 'FAIL' end, ''
union all select 9, 'approvals_guard(): ACL, geen andere grantee dan de eigenaar',
       case when not exists (select 1 from a cross join lateral aclexplode(coalesce(a.proacl, acldefault('f', a.proowner))) x where x.privilege_type = 'EXECUTE' and x.grantee <> a.proowner) then 'PASS' else 'FAIL' end,
       coalesce((select proacl::text from a), '(NULL)')
order by 1;
