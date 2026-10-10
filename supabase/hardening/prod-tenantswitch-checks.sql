-- ============================================================
-- POLDER — controle tenantswitch (migratie 0024). ALLEEN LEZEN: alleen SELECT, eindigt met rollback.
-- Draaien in de Supabase SQL-editor vóór en/of na migratie 0024.
-- Verwacht vóór 0024: 15 × "oud". Verwacht na 0024: 15 × "nieuw". Alles anders: STOP en uitzoeken.
-- ============================================================
begin;
set local search_path = '';
set local quote_all_identifiers = off;

with t(tbl, ouder, fk, alias) as (values
  ('companies', null, null, null), ('invoices', null, null, null), ('documents', null, null, null),
  ('workflow_rules', null, null, null), ('configurations', null, null, null), ('notifications', null, null, null),
  ('integration_plugins', null, null, null),
  ('contacts', 'companies', 'company_id', 'c'), ('departments', 'companies', 'company_id', 'c'),
  ('cost_centers', 'companies', 'company_id', 'c'), ('projects', 'companies', 'company_id', 'c'),
  ('company_codes', 'companies', 'company_id', 'c'), ('approval_settings', 'companies', 'company_id', 'c'),
  ('invoice_lines', 'invoices', 'invoice_id', 'i'), ('payments', 'invoices', 'invoice_id', 'i')),
v as (
  select tbl,
    case when ouder is null then
      E'(restaurant_id IN ( SELECT users.restaurant_id\n   FROM public.users\n  WHERE (users.id = auth.uid())))'
    else pg_catalog.format(E'(%s IN ( SELECT %s.id\n   FROM public.%s %s\n  WHERE (%s.restaurant_id IN ( SELECT users.restaurant_id\n           FROM public.users\n          WHERE (users.id = auth.uid())))))',
                           fk, alias, ouder, alias, alias) end as oud,
    case when ouder is null then '(restaurant_id = public.my_restaurant_id())'
    else pg_catalog.format(E'(EXISTS ( SELECT 1\n   FROM public.%s %s\n  WHERE ((%s.id = %s.%s) AND (%s.restaurant_id = public.my_restaurant_id()))))',
                           ouder, alias, alias, tbl, fk, alias) end as nieuw
  from t)
select v.tbl as tabel,
  case when p.polname is null then 'GEEN POLICY'
       when pg_catalog.pg_get_expr(p.polqual, p.polrelid) = v.oud then 'oud'
       when pg_catalog.pg_get_expr(p.polqual, p.polrelid) = v.nieuw then 'nieuw'
       else 'ONBEKEND' end as stand,
  (select pg_catalog.count(*) from pg_catalog.pg_policy x where x.polrelid = c.oid) as aantal_policies,
  case when p.polcmd = '*' and p.polroles = '{0}'::pg_catalog.oid[] and p.polpermissive and p.polwithcheck is null
       then 'ok' else 'AFWIJKEND' end as vorm,
  c.relrowsecurity as rls_aan,
  case when p.polname is not null
        and pg_catalog.pg_get_expr(p.polqual, p.polrelid) not in (v.oud, v.nieuw)
       then pg_catalog.pg_get_expr(p.polqual, p.polrelid) end as tekst_als_onbekend
from v
left join pg_catalog.pg_class c on c.oid = pg_catalog.to_regclass('public.' || v.tbl)
left join pg_catalog.pg_policy p on p.polrelid = c.oid and p.polname = 'tenant isolation ' || v.tbl
order by 2, 1;

rollback;
