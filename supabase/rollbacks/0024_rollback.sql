-- ============================================================
-- Rollback van migratie 0024: de 15 policies terug naar exact de uitdrukkingen van 0003/0006.
-- Draait alleen als ALLE 15 de nieuwe tekst van 0024 hebben; anders breekt hij af en verandert er niets
-- (geen gedeeltelijk herstel, nooit automatische reparatie). Data, grants en andere policies blijven ongemoeid.
-- ============================================================
begin;
set local search_path = '';
set local quote_all_identifiers = off;
set local lock_timeout = '5s';

create temporary table _ts_tabellen (tbl text primary key, ouder text, fk text, alias text) on commit drop;
insert into _ts_tabellen values
  ('companies', null, null, null), ('invoices', null, null, null), ('documents', null, null, null),
  ('workflow_rules', null, null, null), ('configurations', null, null, null), ('notifications', null, null, null),
  ('integration_plugins', null, null, null),
  ('contacts', 'companies', 'company_id', 'c'), ('departments', 'companies', 'company_id', 'c'),
  ('cost_centers', 'companies', 'company_id', 'c'), ('projects', 'companies', 'company_id', 'c'),
  ('company_codes', 'companies', 'company_id', 'c'), ('approval_settings', 'companies', 'company_id', 'c'),
  ('invoice_lines', 'invoices', 'invoice_id', 'i'), ('payments', 'invoices', 'invoice_id', 'i');

create temporary table _ts_verwacht on commit drop as
select tbl,
  case when ouder is null then
    E'(restaurant_id IN ( SELECT users.restaurant_id\n   FROM public.users\n  WHERE (users.id = auth.uid())))'
  else pg_catalog.format(E'(%s IN ( SELECT %s.id\n   FROM public.%s %s\n  WHERE (%s.restaurant_id IN ( SELECT users.restaurant_id\n           FROM public.users\n          WHERE (users.id = auth.uid())))))',
                         fk, alias, ouder, alias, alias) end as oud,
  case when ouder is null then
    '(restaurant_id = public.my_restaurant_id())'
  else pg_catalog.format(E'(EXISTS ( SELECT 1\n   FROM public.%s %s\n  WHERE ((%s.id = %s.%s) AND (%s.restaurant_id = public.my_restaurant_id()))))',
                         ouder, alias, alias, tbl, fk, alias) end as nieuw
from _ts_tabellen;

-- ---------- VOORAF: alle 15 exact in de 0024-stand ----------
do $$
declare r record; v_fout text := '';
begin
  for r in
    select v.tbl, v.nieuw,
           (select pg_catalog.count(*) from pg_catalog.pg_policy p where p.polrelid = c.oid) as aantal,
           p.polcmd, p.polroles, p.polpermissive, p.polwithcheck is null as geen_check,
           pg_catalog.pg_get_expr(p.polqual, p.polrelid) as tekst
    from _ts_verwacht v
    join pg_catalog.pg_class c on c.oid = pg_catalog.to_regclass('public.' || v.tbl)
    left join pg_catalog.pg_policy p on p.polrelid = c.oid and p.polname = 'tenant isolation ' || v.tbl
    order by v.tbl
  loop
    if r.aantal <> 1 or r.polcmd is null or r.polcmd <> '*' or r.polroles <> '{0}'::pg_catalog.oid[]
       or not r.polpermissive or not r.geen_check or r.tekst is distinct from r.nieuw then
      v_fout := v_fout || r.tbl || '; ';
    end if;
  end loop;
  if v_fout <> '' then
    raise exception '0024-rollback: niet alle policies staan exact in de 0024-stand, niets teruggedraaid. Afwijkend: %', v_fout;
  end if;
end $$;

-- ---------- HERSTEL (tekst van 0003/0006, met search_path public zoals destijds) ----------
set local search_path = public, pg_temp;
alter policy "tenant isolation companies" on public.companies using (
  restaurant_id in (select restaurant_id from users where users.id = auth.uid()));
alter policy "tenant isolation invoices" on public.invoices using (
  restaurant_id in (select restaurant_id from users where users.id = auth.uid()));
alter policy "tenant isolation documents" on public.documents using (
  restaurant_id in (select restaurant_id from users where users.id = auth.uid()));
alter policy "tenant isolation workflow_rules" on public.workflow_rules using (
  restaurant_id in (select restaurant_id from users where users.id = auth.uid()));
alter policy "tenant isolation configurations" on public.configurations using (
  restaurant_id in (select restaurant_id from users where users.id = auth.uid()));
alter policy "tenant isolation notifications" on public.notifications using (
  restaurant_id in (select restaurant_id from users where users.id = auth.uid()));
alter policy "tenant isolation integration_plugins" on public.integration_plugins using (
  restaurant_id in (select restaurant_id from users where users.id = auth.uid()));
alter policy "tenant isolation contacts" on public.contacts using (
  company_id in (select c.id from companies c where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())));
alter policy "tenant isolation departments" on public.departments using (
  company_id in (select c.id from companies c where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())));
alter policy "tenant isolation cost_centers" on public.cost_centers using (
  company_id in (select c.id from companies c where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())));
alter policy "tenant isolation projects" on public.projects using (
  company_id in (select c.id from companies c where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())));
alter policy "tenant isolation company_codes" on public.company_codes using (
  company_id in (select c.id from companies c where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())));
alter policy "tenant isolation approval_settings" on public.approval_settings using (
  company_id in (select c.id from companies c where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())));
alter policy "tenant isolation invoice_lines" on public.invoice_lines using (
  invoice_id in (select i.id from invoices i where i.restaurant_id in (select restaurant_id from users where users.id = auth.uid())));
alter policy "tenant isolation payments" on public.payments using (
  invoice_id in (select i.id from invoices i where i.restaurant_id in (select restaurant_id from users where users.id = auth.uid())));
set local search_path = '';

-- ---------- ACHTERAF: alle 15 exact de oude tekst ----------
do $$
declare r record; v_fout text := '';
begin
  for r in
    select v.tbl, v.oud,
           (select pg_catalog.count(*) from pg_catalog.pg_policy p where p.polrelid = c.oid) as aantal,
           p.polcmd, p.polroles, p.polpermissive, p.polwithcheck is null as geen_check,
           pg_catalog.pg_get_expr(p.polqual, p.polrelid) as tekst
    from _ts_verwacht v
    join pg_catalog.pg_class c on c.oid = pg_catalog.to_regclass('public.' || v.tbl)
    left join pg_catalog.pg_policy p on p.polrelid = c.oid and p.polname = 'tenant isolation ' || v.tbl
    order by v.tbl
  loop
    if r.aantal <> 1 or r.polcmd <> '*' or r.polroles <> '{0}'::pg_catalog.oid[]
       or not r.polpermissive or not r.geen_check or r.tekst is distinct from r.oud then
      v_fout := v_fout || r.tbl || ': ' || pg_catalog.quote_literal(coalesce(r.tekst, '(geen)')) || '; ';
    end if;
  end loop;
  if v_fout <> '' then raise exception '0024-rollback achteraf (niets teruggedraaid): %', v_fout; end if;
end $$;

commit;
