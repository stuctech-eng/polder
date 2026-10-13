-- POLDER - controle PIN-kolommen (migratie 0035, stap 12). ALLEEN LEZEN, eindigt met rollback.
-- Voor 0035: 0034|true|true|10|false|true|true. Na 0035: 0035|true|false|8|false|true|true.
-- De vijf md5's (guards, module_wacht, modules, policies, rechten andere tabellen): voor en na gelijk.
begin;
with c as (select string_agg(column_name, ',' order by column_name) k from information_schema.columns
           where table_schema = 'public' and table_name = 'approval_settings'),
     a as (select has_table_privilege('authenticated', 'public.approval_settings', 'SELECT') tabel,
                  has_column_privilege('authenticated', 'public.approval_settings', 'pin_hash', 'SELECT')
                    or has_column_privilege('authenticated', 'public.approval_settings', 'pin_salt', 'SELECT') pin,
                  (select count(*) from information_schema.columns x where x.table_schema = 'public' and x.table_name = 'approval_settings'
                     and has_column_privilege('authenticated', 'public.approval_settings', x.column_name, 'SELECT')) open)
select
  case when c.k <> 'auto_lock,company_id,created_at,id,is_required,method,notify_email,pin_hash,pin_salt,updated_at' then 'ONBEKEND'
       when a.tabel and a.pin and a.open = 10 then '0034'
       when not a.tabel and not a.pin and a.open = 8 then '0035' else 'ONBEKEND' end as stand,
  c.k = 'auto_lock,company_id,created_at,id,is_required,method,notify_email,pin_hash,pin_salt,updated_at' as kolommen_ok,
  a.pin as pin_leesbaar, a.open as open_kolommen,
  has_column_privilege('anon', 'public.approval_settings', 'method', 'SELECT') as anon_leest,
  has_column_privilege('service_role', 'public.approval_settings', 'pin_hash', 'SELECT') as server_pin,
  has_table_privilege('authenticated', 'public.approval_settings', 'INSERT,UPDATE') as schrijven_ok,
  (select md5(string_agg(f.proname || md5(f.prosrc), '|' order by f.proname)) from pg_proc f
    where f.pronamespace = 'public'::regnamespace and f.prorettype = 'trigger'::regtype and f.proname <> 'module_wacht') as guards_md5,
  (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.module_wacht()')) as module_wacht_md5,
  (select md5(string_agg(r.id || k || public.feature_aan(r.id, k)::text, '|' order by r.id, k)) from public.restaurants r
    cross join (values ('daily_closing'),('payment_registration'),('approval')) v(k)) as modules_md5,
  (select md5(string_agg(tablename || policyname || cmd || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname))
     from pg_policies where schemaname = 'public') as policies_md5,
  (select md5(string_agg(relname || coalesce(array_to_string(relacl, ','), ''), '|' order by relname)) from pg_class
     where relnamespace = 'public'::regnamespace and relkind = 'r' and relname <> 'approval_settings') as rechten_md5
from c, a;
rollback;
