-- ============================================================
-- Migratie 0019 — SECURITY HARDENING STAP 5: H7 (cross-reference integriteit)
-- Plan: docs/security-hardening-plan.md sectie 8. Controles in productie: prod-readonly-checks.sql B30–B42.
-- Geen app-wijziging nodig. Geen data wordt gewijzigd of verwijderd; geen bestaande relatie wordt aangepast.
--
-- Een gewone foreign key controleert alleen of de verwezen rij BESTAAT, niet van welk restaurant/bedrijf die is.
-- Deze migratie voegt BEFORE INSERT/UPDATE-triggers toe die dat wel controleren — ook voor service-role en postgres
-- (géén service-role-bypass). De triggerfuncties zijn SECURITY DEFINER zodat ze de échte ouder zien, ook als RLS die
-- voor de aanroeper zou verbergen.
--
-- A. Kind → ouder (tenant):  open_tabs → companies/departments/cost_centers/projects/contacts, receipts → open_tabs,
--    invoices → companies, invoice_lines → invoices+receipts, approvals → receipts+companies,
--    configurations/workflow_rules → companies, documents → invoices (related_table='invoices'),
--    gebruikersverwijzingen (created_by, closed_by, reopened_by, user_id, published_by, changed_by, recipient_user_id) → users.
-- B. Kind → ouder (bedrijf): afdeling/kostenplaats/project/contact van een rekening horen bij het bedrijf van die rekening;
--    kostenplaats.department_id hoort bij hetzelfde bedrijf.
-- C. Ouder-kant: de sleutelkolommen waarlangs die controles lopen (restaurant_id/company_id van ouders) zijn onveranderlijk,
--    anders kan een ouder achteraf naar een ander restaurant/bedrijf "verhuizen" en de controle omzeilen.
-- Bewust NIET geblokkeerd: zie docs/architecture.md 13.13 (o.a. rekening zonder bedrijf mét afdeling; bon van ander bedrijf op factuur).
-- Rollback: supabase/rollbacks/0019_rollback.sql
-- ============================================================
begin;

-- 0. Veiligheidscontrole: bestaande data moet de nieuwe regels al naleven (anders stoppen we vóór er iets verandert)
do $$
declare v_n bigint;
begin
  if to_regprocedure('public.my_restaurant_id()') is null then
    raise exception 'Stap 1 (migratie 0015) ontbreekt: draai die eerst';
  end if;
  select
    (select count(*) from open_tabs t where
        exists (select 1 from companies c where c.id = t.company_id and c.restaurant_id <> t.restaurant_id)
     or exists (select 1 from departments d join companies c on c.id = d.company_id where d.id = t.department_id and c.restaurant_id <> t.restaurant_id)
     or exists (select 1 from cost_centers d join companies c on c.id = d.company_id where d.id = t.cost_center_id and c.restaurant_id <> t.restaurant_id)
     or exists (select 1 from projects d join companies c on c.id = d.company_id where d.id = t.project_id and c.restaurant_id <> t.restaurant_id)
     or exists (select 1 from contacts d join companies c on c.id = d.company_id where d.id = t.contact_id and c.restaurant_id <> t.restaurant_id))
  + (select count(*) from open_tabs t where t.company_id is not null and (
        exists (select 1 from departments d where d.id = t.department_id and d.company_id <> t.company_id)
     or exists (select 1 from cost_centers d where d.id = t.cost_center_id and d.company_id <> t.company_id)
     or exists (select 1 from projects d where d.id = t.project_id and d.company_id <> t.company_id)
     or exists (select 1 from contacts d where d.id = t.contact_id and d.company_id <> t.company_id)))
  + (select count(*) from cost_centers cc join departments d on d.id = cc.department_id where d.company_id <> cc.company_id)
  + (select count(*) from receipts r join open_tabs t on t.id = r.open_tab_id where t.restaurant_id <> r.restaurant_id)
  + (select count(*) from invoices i join companies c on c.id = i.company_id where c.restaurant_id <> i.restaurant_id)
  + (select count(*) from invoice_lines il join invoices i on i.id = il.invoice_id join receipts r on r.id = il.receipt_id where r.restaurant_id <> i.restaurant_id)
  + (select count(*) from approvals a join receipts r on r.id = a.receipt_id join companies c on c.id = a.company_id where r.restaurant_id <> c.restaurant_id)
  + (select count(*) from configurations x join companies c on c.id = x.company_id where c.restaurant_id <> x.restaurant_id)
  + (select count(*) from workflow_rules x join companies c on c.id = x.company_id where c.restaurant_id <> x.restaurant_id)
  + (select count(*) from documents d join invoices i on d.related_table = 'invoices' and i.id = d.related_id where i.restaurant_id <> d.restaurant_id)
  + (select count(*) from receipts t join users u on u.id = t.created_by where u.restaurant_id <> t.restaurant_id)
  + (select count(*) from daily_closings t join users u on u.id = t.closed_by where u.restaurant_id <> t.restaurant_id)
  + (select count(*) from daily_closings t join users u on u.id = t.reopened_by where u.restaurant_id <> t.restaurant_id)
  + (select count(*) from activity_log t join users u on u.id = t.user_id where u.restaurant_id <> t.restaurant_id)
  + (select count(*) from domain_events t join users u on u.id = t.published_by where u.restaurant_id <> t.restaurant_id)
  + (select count(*) from audit_log t join users u on u.id = t.changed_by where u.restaurant_id <> t.restaurant_id)
  + (select count(*) from notifications t join users u on u.id = t.recipient_user_id where u.restaurant_id <> t.restaurant_id)
  into v_n;
  if v_n > 0 then
    raise exception 'Bestaande data schendt % cross-reference-regel(s): eerst onderzoeken (prod-readonly-checks.sql B30–B42), niets is gewijzigd', v_n;
  end if;
end $$;

-- ------------------------------------------------------------
-- 1. Hulpfuncties (alleen intern gebruikt door de triggerfuncties)
-- ------------------------------------------------------------
-- hoort dit bedrijf bij dit restaurant? (NULL = bedrijf bestaat niet → de gewone FK meldt dat zelf)
create or replace function public.xref_company_in_restaurant(p_company uuid, p_restaurant uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select case when c.id is null then true else c.restaurant_id = p_restaurant end
  from (select 1) x left join public.companies c on c.id = p_company
$$;

-- ------------------------------------------------------------
-- 2. Kind → ouder, per tabel
-- ------------------------------------------------------------
-- open_tabs → companies / departments / cost_centers / projects / contacts
create or replace function public.xref_open_tabs()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid;
  v_restaurant uuid;
  r record;
begin
  if tg_op = 'UPDATE'
     and new.restaurant_id is not distinct from old.restaurant_id and new.company_id is not distinct from old.company_id
     and new.department_id is not distinct from old.department_id and new.cost_center_id is not distinct from old.cost_center_id
     and new.project_id is not distinct from old.project_id and new.contact_id is not distinct from old.contact_id then
    return new;
  end if;

  if new.company_id is not null and not public.xref_company_in_restaurant(new.company_id, new.restaurant_id) then
    raise exception 'open_tabs.company_id wijst naar een bedrijf van een ander restaurant' using errcode = 'check_violation';
  end if;

  for r in
    select 'department_id' as col, 'departments' as tbl, new.department_id as pid
    union all select 'cost_center_id', 'cost_centers', new.cost_center_id
    union all select 'project_id', 'projects', new.project_id
    union all select 'contact_id', 'contacts', new.contact_id
  loop
    continue when r.pid is null;
    execute format('select company_id from public.%I where id = $1', r.tbl) into v_company using r.pid;
    continue when v_company is null;                       -- ouder bestaat niet: de gewone FK meldt dat
    if not public.xref_company_in_restaurant(v_company, new.restaurant_id) then
      raise exception 'open_tabs.% wijst naar een record van een ander restaurant', r.col using errcode = 'check_violation';
    end if;
    if new.company_id is not null and v_company <> new.company_id then
      raise exception 'open_tabs.% hoort niet bij het bedrijf van deze rekening', r.col using errcode = 'check_violation';
    end if;
  end loop;
  return new;
end
$$;

-- cost_centers.department_id: dezelfde bedrijf als de kostenplaats
create or replace function public.xref_cost_centers()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_company uuid;
begin
  if new.department_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.department_id is not distinct from old.department_id and new.company_id is not distinct from old.company_id then
    return new;
  end if;
  select d.company_id into v_company from public.departments d where d.id = new.department_id;
  if v_company is not null and v_company <> new.company_id then
    raise exception 'cost_centers.department_id hoort bij een ander bedrijf dan de kostenplaats' using errcode = 'check_violation';
  end if;
  return new;
end
$$;

-- receipts.open_tab_id (+ created_by wordt door xref_user_ref gedekt)
create or replace function public.xref_receipts()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_restaurant uuid;
begin
  if new.open_tab_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.open_tab_id is not distinct from old.open_tab_id and new.restaurant_id is not distinct from old.restaurant_id then
    return new;
  end if;
  select t.restaurant_id into v_restaurant from public.open_tabs t where t.id = new.open_tab_id;
  if v_restaurant is not null and v_restaurant <> new.restaurant_id then
    raise exception 'receipts.open_tab_id wijst naar een rekening van een ander restaurant' using errcode = 'check_violation';
  end if;
  return new;
end
$$;

-- invoices.company_id
create or replace function public.xref_invoices()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'UPDATE' and new.company_id is not distinct from old.company_id and new.restaurant_id is not distinct from old.restaurant_id then
    return new;
  end if;
  if not public.xref_company_in_restaurant(new.company_id, new.restaurant_id) then
    raise exception 'invoices.company_id wijst naar een bedrijf van een ander restaurant' using errcode = 'check_violation';
  end if;
  return new;
end
$$;

-- invoice_lines: factuur en bon moeten van hetzelfde restaurant zijn
create or replace function public.xref_invoice_lines()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_inv uuid; v_rec uuid;
begin
  if new.receipt_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.invoice_id is not distinct from old.invoice_id and new.receipt_id is not distinct from old.receipt_id then
    return new;
  end if;
  select i.restaurant_id into v_inv from public.invoices i where i.id = new.invoice_id;
  select r.restaurant_id into v_rec from public.receipts r where r.id = new.receipt_id;
  if v_inv is not null and v_rec is not null and v_inv <> v_rec then
    raise exception 'invoice_lines: factuur en bon horen bij verschillende restaurants' using errcode = 'check_violation';
  end if;
  return new;
end
$$;

-- approvals: bon en bedrijf moeten van hetzelfde restaurant zijn
create or replace function public.xref_approvals()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_rec uuid; v_comp uuid;
begin
  if tg_op = 'UPDATE' and new.receipt_id is not distinct from old.receipt_id and new.company_id is not distinct from old.company_id then
    return new;
  end if;
  select r.restaurant_id into v_rec from public.receipts r where r.id = new.receipt_id;
  select c.restaurant_id into v_comp from public.companies c where c.id = new.company_id;
  if v_rec is not null and v_comp is not null and v_rec <> v_comp then
    raise exception 'approvals: bon en bedrijf horen bij verschillende restaurants' using errcode = 'check_violation';
  end if;
  return new;
end
$$;

-- configurations / workflow_rules: company_id (optioneel) moet bij het eigen restaurant horen
create or replace function public.xref_company_scoped()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.company_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.company_id is not distinct from old.company_id and new.restaurant_id is not distinct from old.restaurant_id then
    return new;
  end if;
  if not public.xref_company_in_restaurant(new.company_id, new.restaurant_id) then
    raise exception '%.company_id wijst naar een bedrijf van een ander restaurant', tg_table_name using errcode = 'check_violation';
  end if;
  return new;
end
$$;

-- documents → invoices (alleen related_table = 'invoices'; andere waarden worden niet gecontroleerd)
create or replace function public.xref_documents()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_restaurant uuid;
begin
  if new.related_table is distinct from 'invoices' then return new; end if;
  if tg_op = 'UPDATE' and new.related_table is not distinct from old.related_table and new.related_id is not distinct from old.related_id
     and new.restaurant_id is not distinct from old.restaurant_id then
    return new;
  end if;
  select i.restaurant_id into v_restaurant from public.invoices i where i.id = new.related_id;
  if v_restaurant is not null and v_restaurant <> new.restaurant_id then
    raise exception 'documents.related_id wijst naar een factuur van een ander restaurant' using errcode = 'check_violation';
  end if;
  return new;
end
$$;

-- gebruikersverwijzingen: de gebruiker moet bij het restaurant van de rij horen (kolomnamen via trigger-argumenten)
create or replace function public.xref_user_ref()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_col text; v_uid uuid; v_old uuid; v_restaurant uuid;
begin
  foreach v_col in array tg_argv loop
    v_uid := nullif(to_jsonb(new) ->> v_col, '')::uuid;
    continue when v_uid is null;
    if tg_op = 'UPDATE' then
      v_old := nullif(to_jsonb(old) ->> v_col, '')::uuid;
      continue when v_uid is not distinct from v_old and new.restaurant_id is not distinct from old.restaurant_id;
    end if;
    select u.restaurant_id into v_restaurant from public.users u where u.id = v_uid;
    if v_restaurant is not null and v_restaurant <> new.restaurant_id then
      raise exception '%.% wijst naar een gebruiker van een ander restaurant', tg_table_name, v_col using errcode = 'check_violation';
    end if;
  end loop;
  return new;
end
$$;

-- ------------------------------------------------------------
-- 3. Ouder-kant: sleutelkolommen onveranderlijk (kolomnamen via trigger-argumenten)
-- ------------------------------------------------------------
create or replace function public.xref_keys_immutable()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare v_col text;
begin
  foreach v_col in array tg_argv loop
    if (to_jsonb(new) ->> v_col) is distinct from (to_jsonb(old) ->> v_col) then
      raise exception '%.% is onveranderlijk', tg_table_name, v_col using errcode = 'check_violation';
    end if;
  end loop;
  return new;
end
$$;

-- ------------------------------------------------------------
-- 4. Triggers koppelen
-- ------------------------------------------------------------
drop trigger if exists xref_open_tabs on public.open_tabs;
create trigger xref_open_tabs before insert or update of restaurant_id, company_id, department_id, cost_center_id, project_id, contact_id
  on public.open_tabs for each row execute function public.xref_open_tabs();

drop trigger if exists xref_cost_centers on public.cost_centers;
create trigger xref_cost_centers before insert or update of company_id, department_id
  on public.cost_centers for each row execute function public.xref_cost_centers();

drop trigger if exists xref_receipts on public.receipts;
create trigger xref_receipts before insert or update of restaurant_id, open_tab_id
  on public.receipts for each row execute function public.xref_receipts();

drop trigger if exists xref_invoices on public.invoices;
create trigger xref_invoices before insert or update of restaurant_id, company_id
  on public.invoices for each row execute function public.xref_invoices();

drop trigger if exists xref_invoice_lines on public.invoice_lines;
create trigger xref_invoice_lines before insert or update of invoice_id, receipt_id
  on public.invoice_lines for each row execute function public.xref_invoice_lines();

drop trigger if exists xref_approvals on public.approvals;
create trigger xref_approvals before insert or update of receipt_id, company_id
  on public.approvals for each row execute function public.xref_approvals();

drop trigger if exists xref_company_scoped on public.configurations;
create trigger xref_company_scoped before insert or update of restaurant_id, company_id
  on public.configurations for each row execute function public.xref_company_scoped();
drop trigger if exists xref_company_scoped on public.workflow_rules;
create trigger xref_company_scoped before insert or update of restaurant_id, company_id
  on public.workflow_rules for each row execute function public.xref_company_scoped();

drop trigger if exists xref_documents on public.documents;
create trigger xref_documents before insert or update of restaurant_id, related_table, related_id
  on public.documents for each row execute function public.xref_documents();

drop trigger if exists xref_user_ref on public.receipts;
create trigger xref_user_ref before insert or update of restaurant_id, created_by
  on public.receipts for each row execute function public.xref_user_ref('created_by');
drop trigger if exists xref_user_ref on public.daily_closings;
create trigger xref_user_ref before insert or update of restaurant_id, closed_by, reopened_by
  on public.daily_closings for each row execute function public.xref_user_ref('closed_by', 'reopened_by');
drop trigger if exists xref_user_ref on public.notifications;
create trigger xref_user_ref before insert or update of restaurant_id, recipient_user_id
  on public.notifications for each row execute function public.xref_user_ref('recipient_user_id');
-- logboeken zijn append-only (stap 4): alleen INSERT is relevant
drop trigger if exists xref_user_ref on public.activity_log;
create trigger xref_user_ref before insert on public.activity_log for each row execute function public.xref_user_ref('user_id');
drop trigger if exists xref_user_ref on public.domain_events;
create trigger xref_user_ref before insert on public.domain_events for each row execute function public.xref_user_ref('published_by');
drop trigger if exists xref_user_ref on public.audit_log;
create trigger xref_user_ref before insert on public.audit_log for each row execute function public.xref_user_ref('changed_by');

-- ouder-kant
drop trigger if exists xref_keys_immutable on public.companies;
create trigger xref_keys_immutable before update of restaurant_id on public.companies
  for each row execute function public.xref_keys_immutable('restaurant_id');
drop trigger if exists xref_keys_immutable on public.departments;
create trigger xref_keys_immutable before update of company_id on public.departments
  for each row execute function public.xref_keys_immutable('company_id');
drop trigger if exists xref_keys_immutable on public.cost_centers;
create trigger xref_keys_immutable before update of company_id on public.cost_centers
  for each row execute function public.xref_keys_immutable('company_id');
drop trigger if exists xref_keys_immutable on public.projects;
create trigger xref_keys_immutable before update of company_id on public.projects
  for each row execute function public.xref_keys_immutable('company_id');
drop trigger if exists xref_keys_immutable on public.contacts;
create trigger xref_keys_immutable before update of company_id on public.contacts
  for each row execute function public.xref_keys_immutable('company_id');
drop trigger if exists xref_keys_immutable on public.open_tabs;
create trigger xref_keys_immutable before update of restaurant_id on public.open_tabs
  for each row execute function public.xref_keys_immutable('restaurant_id');
drop trigger if exists xref_keys_immutable on public.receipts;
create trigger xref_keys_immutable before update of restaurant_id on public.receipts
  for each row execute function public.xref_keys_immutable('restaurant_id');
drop trigger if exists xref_keys_immutable on public.invoices;
create trigger xref_keys_immutable before update of restaurant_id on public.invoices
  for each row execute function public.xref_keys_immutable('restaurant_id');

-- ------------------------------------------------------------
-- 5. Functies zijn alleen voor triggers: niemand hoeft ze direct aan te roepen
-- ------------------------------------------------------------
revoke all on function public.xref_company_in_restaurant(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.xref_open_tabs()      from public, anon, authenticated, service_role;
revoke all on function public.xref_cost_centers()   from public, anon, authenticated, service_role;
revoke all on function public.xref_receipts()       from public, anon, authenticated, service_role;
revoke all on function public.xref_invoices()       from public, anon, authenticated, service_role;
revoke all on function public.xref_invoice_lines()  from public, anon, authenticated, service_role;
revoke all on function public.xref_approvals()      from public, anon, authenticated, service_role;
revoke all on function public.xref_company_scoped() from public, anon, authenticated, service_role;
revoke all on function public.xref_documents()      from public, anon, authenticated, service_role;
revoke all on function public.xref_user_ref()       from public, anon, authenticated, service_role;
revoke all on function public.xref_keys_immutable() from public, anon, authenticated, service_role;

commit;
