-- POLDER - controle rolrechten facturen (migraties 0031-0032, hardening stap 10). ALLEEN LEZEN, eindigt met rollback.
-- Voor 0031: stand 0030, 4/4/0, rechten_ok leeg. Na 0032: stand 0032, 11/0/3, rechten_ok true.
-- Altijd: guards_md5 = 287f55d538eeb47386154595baf42dee; module_wacht_md5 en modules_md5 voor en na gelijk.
begin;
with p as (select count(*) n, count(*) filter (where cmd = 'ALL') a from pg_policies
           where schemaname = 'public' and tablename in ('invoices','invoice_lines','payments','documents')),
     t as (select count(*) n from pg_trigger where tgname in ('invoices_guard','invoice_child_guard'))
select
  case when to_regprocedure('public.module_wacht()') is null then 'ONBEKEND'
       when p.n = 4 and p.a = 4 and t.n = 0 then '0030'
       when p.n = 11 and p.a = 0 and t.n = 0 then '0031'
       when p.n = 11 and p.a = 0 and t.n = 3 then '0032' else 'ONBEKEND' end as stand,
  p.n as policies, p.a as policies_all, t.n as wacht_triggers,
  case when t.n = 0 then null else
    (select bool_and(prosecdef and proconfig = '{"search_path=public, pg_temp"}'
       and not has_function_privilege('anon', oid, 'EXECUTE') and not has_function_privilege('authenticated', oid, 'EXECUTE')
       and not has_function_privilege('service_role', oid, 'EXECUTE')) and count(*) = 2
     from pg_proc where pronamespace = 'public'::regnamespace and proname in ('invoices_guard','invoice_child_guard'))
    and not exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('invoices','invoice_lines','payments','documents')
                    and roles <> '{authenticated}')
  end as rechten_ok,
  (select md5(string_agg(f.proname || md5(f.prosrc), '|' order by f.proname)) from pg_proc f
    where f.pronamespace = 'public'::regnamespace and f.prorettype = 'trigger'::regtype
      and f.proname not in ('module_wacht','invoices_guard','invoice_child_guard')) as guards_md5,
  (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.module_wacht()')) as module_wacht_md5,
  (select md5(string_agg(r.id || k || public.feature_aan(r.id, k)::text, '|' order by r.id, k)) from public.restaurants r
    cross join (values ('daily_closing'),('payment_registration'),('approval')) v(k)) as modules_md5
from p, t;
rollback;
