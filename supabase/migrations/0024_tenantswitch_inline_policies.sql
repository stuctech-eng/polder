-- ============================================================
-- Migratie 0024 — FASE 1 MEERDERE RESTAURANTS: tenantswitch van de 15 oude inline-policies
-- Vereist 0015 (my_restaurant_id() fail-closed). Geen app-wijziging. Bestaande data wordt niet gewijzigd.
--
--  De 15 tabellen die nog de oude controle uit 0003/0006 gebruikten
--  ("restaurant_id in (select restaurant_id from users where users.id = auth.uid())", zonder is_active)
--  lopen voortaan via public.my_restaurant_id(). Gevolg: een gedeactiveerde gebruiker ziet en wijzigt hier niets meer;
--  voor een actieve gebruiker verandert niets. Basis om later een restaurant betrouwbaar uit te kunnen zetten.
--
--  Alleen de USING-uitdrukking wijzigt (ALTER POLICY). Naam, commando (ALL), rol (public) en het ontbreken van
--  een aparte WITH CHECK blijven gelijk. 7 tabellen direct op restaurant_id, 8 via de oudertabel.
--
--  Controles (in deze transactie; elke afwijking breekt af en er verandert niets):
--   vooraf : my_restaurant_id() bestaat (SECURITY DEFINER); per tabel RLS aan, precies 1 policy met de verwachte naam,
--            ALL, rol public, geen WITH CHECK, en exact de oude tekst. Een gemengde stand of "al uitgevoerd" breekt af.
--   achteraf: per tabel weer precies 1 policy in dezelfde vorm, met exact de nieuwe tekst.
--  Tekst = pg_get_expr(polqual, polrelid) onder search_path = '' (gemeten gelijk op PostgreSQL 16 en 17).
-- Rollback: supabase/rollbacks/0024_rollback.sql
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

-- verwachte teksten (zoals Postgres ze teruggeeft onder search_path = '')
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

-- ---------- VOORAF ----------
do $$
declare r record; v_oud int := 0; v_nieuw int := 0; v_fout text := '';
begin
  if pg_catalog.to_regprocedure('public.my_restaurant_id()') is null
     or not (select p.prosecdef from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('public.my_restaurant_id()')) then
    raise exception '0024: public.my_restaurant_id() ontbreekt of is geen SECURITY DEFINER (migratie 0015 eerst)';
  end if;
  for r in
    select v.tbl, v.oud, v.nieuw, c.relrowsecurity as rls,
           (select pg_catalog.count(*) from pg_catalog.pg_policy p where p.polrelid = c.oid) as aantal,
           p.polname, p.polcmd, p.polroles, p.polpermissive, p.polwithcheck is null as geen_check,
           pg_catalog.pg_get_expr(p.polqual, p.polrelid) as tekst
    from _ts_verwacht v
    left join pg_catalog.pg_class c on c.oid = pg_catalog.to_regclass('public.' || v.tbl)
    left join pg_catalog.pg_policy p on p.polrelid = c.oid and p.polname = 'tenant isolation ' || v.tbl
    order by v.tbl
  loop
    if r.rls is null then v_fout := v_fout || r.tbl || ': tabel ontbreekt; '; continue; end if;
    if not r.rls then v_fout := v_fout || r.tbl || ': RLS staat uit; '; end if;
    if r.aantal <> 1 or r.polname is null then v_fout := v_fout || r.tbl || ': niet precies 1 policy "tenant isolation ' || r.tbl || '"; '; continue; end if;
    if r.polcmd <> '*' or r.polroles <> '{0}'::pg_catalog.oid[] or not r.polpermissive or not r.geen_check then
      v_fout := v_fout || r.tbl || ': afwijkende vorm (cmd/rol/permissive/with check); ';
    end if;
    if r.tekst = r.oud then v_oud := v_oud + 1;
    elsif r.tekst = r.nieuw then v_nieuw := v_nieuw + 1;
    else v_fout := v_fout || r.tbl || ': onbekende tekst ' || pg_catalog.quote_literal(r.tekst) || '; ';
    end if;
  end loop;
  if v_fout <> '' then raise exception '0024 vooraf: %', v_fout; end if;
  if v_nieuw = 15 then raise exception '0024 is al uitgevoerd (alle 15 policies hebben de nieuwe tekst)'; end if;
  if v_oud <> 15 then raise exception '0024 vooraf: gemengde stand (% oud, % nieuw): eerst beoordelen', v_oud, v_nieuw; end if;
end $$;

-- ---------- WIJZIGING ----------
-- Directe tabellen (7)
alter policy "tenant isolation companies"           on public.companies           using (restaurant_id = public.my_restaurant_id());
alter policy "tenant isolation invoices"            on public.invoices            using (restaurant_id = public.my_restaurant_id());
alter policy "tenant isolation documents"           on public.documents           using (restaurant_id = public.my_restaurant_id());
alter policy "tenant isolation workflow_rules"      on public.workflow_rules      using (restaurant_id = public.my_restaurant_id());
alter policy "tenant isolation configurations"      on public.configurations      using (restaurant_id = public.my_restaurant_id());
alter policy "tenant isolation notifications"       on public.notifications       using (restaurant_id = public.my_restaurant_id());
alter policy "tenant isolation integration_plugins" on public.integration_plugins using (restaurant_id = public.my_restaurant_id());

-- Kindtabellen via de ouder (8) — hebben geen eigen restaurant_id
alter policy "tenant isolation contacts" on public.contacts using (
  exists (select 1 from public.companies c where c.id = contacts.company_id and c.restaurant_id = public.my_restaurant_id()));
alter policy "tenant isolation departments" on public.departments using (
  exists (select 1 from public.companies c where c.id = departments.company_id and c.restaurant_id = public.my_restaurant_id()));
alter policy "tenant isolation cost_centers" on public.cost_centers using (
  exists (select 1 from public.companies c where c.id = cost_centers.company_id and c.restaurant_id = public.my_restaurant_id()));
alter policy "tenant isolation projects" on public.projects using (
  exists (select 1 from public.companies c where c.id = projects.company_id and c.restaurant_id = public.my_restaurant_id()));
alter policy "tenant isolation company_codes" on public.company_codes using (
  exists (select 1 from public.companies c where c.id = company_codes.company_id and c.restaurant_id = public.my_restaurant_id()));
alter policy "tenant isolation approval_settings" on public.approval_settings using (
  exists (select 1 from public.companies c where c.id = approval_settings.company_id and c.restaurant_id = public.my_restaurant_id()));
alter policy "tenant isolation invoice_lines" on public.invoice_lines using (
  exists (select 1 from public.invoices i where i.id = invoice_lines.invoice_id and i.restaurant_id = public.my_restaurant_id()));
alter policy "tenant isolation payments" on public.payments using (
  exists (select 1 from public.invoices i where i.id = payments.invoice_id and i.restaurant_id = public.my_restaurant_id()));

-- ---------- ACHTERAF ----------
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
       or not r.polpermissive or not r.geen_check then
      v_fout := v_fout || r.tbl || ': vorm gewijzigd; ';
    end if;
    if r.tekst is distinct from r.nieuw then
      v_fout := v_fout || r.tbl || ': tekst ' || pg_catalog.quote_literal(coalesce(r.tekst, '(geen)')) || '; ';
    end if;
  end loop;
  if v_fout <> '' then raise exception '0024 achteraf (niets gewijzigd): %', v_fout; end if;
end $$;

commit;
