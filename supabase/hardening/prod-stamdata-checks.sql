-- POLDER - controle rolrechten stap 11 (migraties 0033-0034). ALLEEN LEZEN, eindigt met rollback.
-- Voor 0033: stand 0032, 13/13/13, dicht_ok leeg. Na 0033: 0033, 20/7/7. Na 0034: 0034, 22/0/0, dicht_ok true.
-- guards_md5, module_wacht_md5, modules_md5 en overige_md5: voor en na gelijk (noteren bij de eerste controle).
begin;
with l as (select array['daily_closings','companies','departments','cost_centers','projects','company_codes','configurations',
             'workflow_rules','approval_settings','contacts','integration_plugins','email_settings','notifications']::text[] a),
     p as (select count(*) n, count(*) filter (where cmd = 'ALL') a from pg_policies, l where schemaname = 'public' and tablename = any(l.a)),
     g as (select count(*) n from pg_policies where schemaname = 'public' and cmd = 'ALL')
select
  case when p.n = 13 and p.a = 13 then '0032' when p.n = 20 and p.a = 7 then '0033'
       when p.n = 22 and p.a = 0 and g.n = 0 then '0034' else 'ONBEKEND' end as stand,
  p.n as policies, p.a as policies_all, g.n as all_in_public,
  case when p.n <> 22 then null else
    (select count(*) = 4 from pg_class where relnamespace = 'public'::regnamespace and relrowsecurity
       and relname in ('contacts','integration_plugins','email_settings','notifications'))
    and not exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('contacts','integration_plugins','email_settings','notifications'))
    and not exists (select 1 from pg_policies, l where schemaname = 'public' and tablename = any(l.a) and (cmd = 'DELETE' or roles <> '{authenticated}'))
    and coalesce((select with_check like '%closed_by = auth.uid()%' from pg_policies where policyname = 'daily_closings insert'), false)
  end as dicht_ok,
  (select md5(string_agg(f.proname || md5(f.prosrc), '|' order by f.proname)) from pg_proc f
    where f.pronamespace = 'public'::regnamespace and f.prorettype = 'trigger'::regtype and f.proname <> 'module_wacht') as guards_md5,
  (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.module_wacht()')) as module_wacht_md5,
  (select md5(string_agg(r.id || k || public.feature_aan(r.id, k)::text, '|' order by r.id, k)) from public.restaurants r
    cross join (values ('daily_closing'),('payment_registration'),('approval')) v(k)) as modules_md5,
  (select md5(string_agg(tablename || policyname || cmd || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname))
     from pg_policies, l where schemaname = 'public' and not (tablename = any(l.a))) as overige_md5
from p, g;
rollback;
