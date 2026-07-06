-- ============================================================
-- Migratie 0003: RLS-policies herstellen (bugfix)
-- Oorzaak: "Enable automatic RLS" zette RLS aan op ALLE tabellen bij
-- aanmaak, inclusief 'users' — zonder eigen policy was die daardoor
-- ontoegankelijk, wat de tenant-isolatiecheck op andere tabellen liet
-- falen (want die checkt via 'users' welk restaurant bij jou hoort).
-- ============================================================

-- KRITIEK: zonder dit kan niemand ooit zijn eigen restaurant_id opzoeken
drop policy if exists "users can see own profile" on users;
create policy "users can see own profile" on users
  for select using (id = auth.uid());

alter table restaurants enable row level security;
drop policy if exists "tenant isolation restaurants" on restaurants;
create policy "tenant isolation restaurants" on restaurants
  for all using (
    id in (select restaurant_id from users where users.id = auth.uid())
  );

-- Bedrijven-gerelateerde tabellen die via company_id gekoppeld zijn
-- (geen eigen restaurant_id-kolom, dus check via companies)
alter table contacts enable row level security;
drop policy if exists "tenant isolation contacts" on contacts;
create policy "tenant isolation contacts" on contacts
  for all using (
    company_id in (
      select c.id from companies c
      where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

alter table departments enable row level security;
drop policy if exists "tenant isolation departments" on departments;
create policy "tenant isolation departments" on departments
  for all using (
    company_id in (
      select c.id from companies c
      where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

alter table cost_centers enable row level security;
drop policy if exists "tenant isolation cost_centers" on cost_centers;
create policy "tenant isolation cost_centers" on cost_centers
  for all using (
    company_id in (
      select c.id from companies c
      where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

alter table projects enable row level security;
drop policy if exists "tenant isolation projects" on projects;
create policy "tenant isolation projects" on projects
  for all using (
    company_id in (
      select c.id from companies c
      where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

-- Tabellen met eigen restaurant_id-kolom: rechtstreekse check
drop policy if exists "tenant isolation companies" on companies;
create policy "tenant isolation companies" on companies
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

drop policy if exists "tenant isolation open_tabs" on open_tabs;
create policy "tenant isolation open_tabs" on open_tabs
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

alter table receipt_lines enable row level security;
drop policy if exists "tenant isolation receipt_lines" on receipt_lines;
create policy "tenant isolation receipt_lines" on receipt_lines
  for all using (
    receipt_id in (
      select r.id from receipts r
      where r.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

drop policy if exists "tenant isolation receipts" on receipts;
create policy "tenant isolation receipts" on receipts
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

drop policy if exists "tenant isolation invoices" on invoices;
create policy "tenant isolation invoices" on invoices
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

alter table invoice_lines enable row level security;
drop policy if exists "tenant isolation invoice_lines" on invoice_lines;
create policy "tenant isolation invoice_lines" on invoice_lines
  for all using (
    invoice_id in (
      select i.id from invoices i
      where i.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

alter table documents enable row level security;
drop policy if exists "tenant isolation documents" on documents;
create policy "tenant isolation documents" on documents
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

alter table workflow_rules enable row level security;
drop policy if exists "tenant isolation workflow_rules" on workflow_rules;
create policy "tenant isolation workflow_rules" on workflow_rules
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

alter table configurations enable row level security;
drop policy if exists "tenant isolation configurations" on configurations;
create policy "tenant isolation configurations" on configurations
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

alter table payments enable row level security;
drop policy if exists "tenant isolation payments" on payments;
create policy "tenant isolation payments" on payments
  for all using (
    invoice_id in (
      select i.id from invoices i
      where i.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

alter table notifications enable row level security;
drop policy if exists "tenant isolation notifications" on notifications;
create policy "tenant isolation notifications" on notifications
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

drop policy if exists "tenant isolation domain_events" on domain_events;
create policy "tenant isolation domain_events" on domain_events
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

drop policy if exists "tenant isolation audit_log" on audit_log;
create policy "tenant isolation audit_log" on audit_log
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

drop policy if exists "tenant isolation activity_log" on activity_log;
create policy "tenant isolation activity_log" on activity_log
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

alter table integration_plugins enable row level security;
drop policy if exists "tenant isolation integration_plugins" on integration_plugins;
create policy "tenant isolation integration_plugins" on integration_plugins
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

-- email_settings (alleen als migratie 0002 al gedraaid is — anders overslaan)
do $$
begin
  if to_regclass('public.email_settings') is not null then
    execute 'drop policy if exists "tenant isolation email_settings" on email_settings';
    execute 'create policy "tenant isolation email_settings" on email_settings
      for all using (
        restaurant_id in (select restaurant_id from users where users.id = auth.uid())
      )';
  end if;
end $$;
