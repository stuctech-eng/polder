-- ============================================================
-- POLDER — Security Hardening STAP 0: STAGING-SEED (ALLEEN STAGING / LOKALE TESTDB!)
-- ============================================================
-- Maakt twee testrestaurants (A en B), per restaurant vijf rollen + één gedeactiveerde
-- gebruiker, een wees-auth-account zonder profiel, en voorbeelddata in alle statussen.
--
--   !!! NOOIT IN PRODUCTIE DRAAIEN !!!  Het script weigert te draaien als het productierestaurant
--   bestaat, en wist/vervangt de vaste testrijen (Staging A / Staging B) bij elke run.
--
-- Wachtwoord van alle testaccounts: Staging-Test-2026!   (uitsluitend voor de testomgeving)
-- Restaurant C (leeg, alleen voor verwijder-tests): d.owner@ en d.bediening@staging.test.
-- E-mailadressen: a.owner@staging.test, a.manager@, a.admin@, a.bediening@, a.keuken@,
--                 a.inactive@ (gedeactiveerd), idem b.*@staging.test, en orphan@staging.test (geen profiel).
-- ============================================================

do $guard$
begin
  if exists (select 1 from restaurants where id = '374a9aa4-a34e-4ec0-ab24-78988a38b0fb') then
    raise exception 'STOP: dit lijkt de PRODUCTIEDATABASE (productierestaurant gevonden). Seed niet uitgevoerd.';
  end if;
end
$guard$;

-- marker: het testharnas weigert te draaien zonder deze tabel (extra bescherming tegen productie)
create table if not exists public._polder_staging_marker (created_at timestamptz default now(), note text);
insert into public._polder_staging_marker (note) select 'staging-seed' where not exists (select 1 from public._polder_staging_marker);

-- opruimen vorige run (eerst restaurants — dat ruimt de profielen mee op; pas daarna de auth-accounts)
delete from restaurants where id in ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001');
delete from auth.users where id::text like 'a0000000-%' or id::text like 'b0000000-%' or id::text like 'c0000000-%' or id::text like 'd0000000-%';
delete from storage.objects where bucket_id = 'documents' and (name like 'a0000000-0000-0000-0000-000000000001/%' or name like 'b0000000-0000-0000-0000-000000000001/%');
insert into storage.buckets (id, name, public) values ('documents','documents',false) on conflict (id) do nothing;
insert into restaurants (id, name) values ('a0000000-0000-0000-0000-000000000001', 'Staging A'), ('b0000000-0000-0000-0000-000000000001', 'Staging B'), ('d0000000-0000-0000-0000-000000000001', 'Staging C (leeg)');
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, raw_app_meta_data, raw_user_meta_data, is_super_admin, is_sso_user)
values
('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000010','authenticated','authenticated','a.owner@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000011','authenticated','authenticated','a.manager@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000012','authenticated','authenticated','a.admin@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000013','authenticated','authenticated','a.bediening@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000014','authenticated','authenticated','a.keuken@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000015','authenticated','authenticated','a.inactive@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','b0000000-0000-0000-0000-000000000010','authenticated','authenticated','b.owner@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','b0000000-0000-0000-0000-000000000011','authenticated','authenticated','b.manager@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','b0000000-0000-0000-0000-000000000012','authenticated','authenticated','b.admin@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','b0000000-0000-0000-0000-000000000013','authenticated','authenticated','b.bediening@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','b0000000-0000-0000-0000-000000000014','authenticated','authenticated','b.keuken@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','b0000000-0000-0000-0000-000000000015','authenticated','authenticated','b.inactive@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','c0000000-0000-0000-0000-000000000001','authenticated','authenticated','orphan@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','d0000000-0000-0000-0000-000000000010','authenticated','authenticated','d.owner@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false),
('00000000-0000-0000-0000-000000000000','d0000000-0000-0000-0000-000000000013','authenticated','authenticated','d.bediening@staging.test',crypt('Staging-Test-2026!', gen_salt('bf')),now(),now(),now(),'','','','','','{"provider":"email","providers":["email"]}','{}',false,false);
insert into users (id, restaurant_id, full_name, role, is_active) values
('a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000001','Staging A owner','owner',true),
('a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000001','Staging A manager','manager',true),
('a0000000-0000-0000-0000-000000000012','a0000000-0000-0000-0000-000000000001','Staging A admin','administratie',true),
('a0000000-0000-0000-0000-000000000013','a0000000-0000-0000-0000-000000000001','Staging A bediening','bediening',true),
('a0000000-0000-0000-0000-000000000014','a0000000-0000-0000-0000-000000000001','Staging A keuken','keuken',true),
('a0000000-0000-0000-0000-000000000015','a0000000-0000-0000-0000-000000000001','Staging A inactive','bediening',false),
('b0000000-0000-0000-0000-000000000010','b0000000-0000-0000-0000-000000000001','Staging B owner','owner',true),
('b0000000-0000-0000-0000-000000000011','b0000000-0000-0000-0000-000000000001','Staging B manager','manager',true),
('b0000000-0000-0000-0000-000000000012','b0000000-0000-0000-0000-000000000001','Staging B admin','administratie',true),
('b0000000-0000-0000-0000-000000000013','b0000000-0000-0000-0000-000000000001','Staging B bediening','bediening',true),
('b0000000-0000-0000-0000-000000000014','b0000000-0000-0000-0000-000000000001','Staging B keuken','keuken',true),
('b0000000-0000-0000-0000-000000000015','b0000000-0000-0000-0000-000000000001','Staging B inactive','bediening',false),
('d0000000-0000-0000-0000-000000000010','d0000000-0000-0000-0000-000000000001','Staging C owner','owner',true),
('d0000000-0000-0000-0000-000000000013','d0000000-0000-0000-0000-000000000001','Staging C bediening','bediening',true);

-- ===== data restaurant A =====
insert into companies (id, restaurant_id, name) values ('a0000000-0000-0000-0000-000000000100','a0000000-0000-0000-0000-000000000001','Bedrijf 1 (A)'), ('a0000000-0000-0000-0000-000000000105','a0000000-0000-0000-0000-000000000001','Bedrijf 2 (A)');
insert into departments (id, company_id, name) values ('a0000000-0000-0000-0000-000000000101','a0000000-0000-0000-0000-000000000100','Afdeling 1'), ('a0000000-0000-0000-0000-000000000106','a0000000-0000-0000-0000-000000000105','Afdeling bedrijf 2');
insert into cost_centers (id, company_id, department_id, name) values ('a0000000-0000-0000-0000-000000000102','a0000000-0000-0000-0000-000000000100','a0000000-0000-0000-0000-000000000101','Kostenplaats 1');
insert into projects (id, company_id, name) values ('a0000000-0000-0000-0000-000000000103','a0000000-0000-0000-0000-000000000100','Project 1');
insert into contacts (id, company_id, full_name) values ('a0000000-0000-0000-0000-000000000104','a0000000-0000-0000-0000-000000000100','Contact 1');
insert into open_tabs (id, restaurant_id, company_id, department_id, cost_center_id, project_id, contact_id, status, closed_at) values
  ('a0000000-0000-0000-0000-000000000200','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000100','a0000000-0000-0000-0000-000000000101','a0000000-0000-0000-0000-000000000102','a0000000-0000-0000-0000-000000000103','a0000000-0000-0000-0000-000000000104','open',null),
  ('a0000000-0000-0000-0000-000000000201','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000100',null,null,null,null,'closed',now()),
  ('a0000000-0000-0000-0000-000000000202','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000100',null,null,null,null,'invoiced',now()),
  ('a0000000-0000-0000-0000-000000000203','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000100',null,null,null,null,'closed',now()),
  ('a0000000-0000-0000-0000-000000000204','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000100',null,null,null,null,'open',null);
insert into receipts (id, restaurant_id, open_tab_id, receipt_number, status, total, receipt_date, created_by) values
  ('a0000000-0000-0000-0000-000000000300','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000200','B-300','linked',10.00,current_date,'a0000000-0000-0000-0000-000000000013'),
  ('a0000000-0000-0000-0000-000000000301','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000200','B-301','pending_approval',20.00,current_date,'a0000000-0000-0000-0000-000000000013'),
  ('a0000000-0000-0000-0000-000000000302','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000202','B-302','locked',30.00,current_date,'a0000000-0000-0000-0000-000000000013'),
  ('a0000000-0000-0000-0000-000000000303','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000201','B-303','approved',40.00,current_date,'a0000000-0000-0000-0000-000000000013');
insert into receipt_lines (id, receipt_id, description, quantity, unit_price, vat_rate, line_total) values
  ('a0000000-0000-0000-0000-000000000310','a0000000-0000-0000-0000-000000000300','Koffie',2,5.00,9,10.00), ('a0000000-0000-0000-0000-000000000311','a0000000-0000-0000-0000-000000000302','Lunch',1,30.00,9,30.00);
insert into approvals (id, receipt_id, company_id, method, status, verification_code, approved_by, approved_at) values
  ('a0000000-0000-0000-0000-000000000400','a0000000-0000-0000-0000-000000000301','a0000000-0000-0000-0000-000000000100','qr','pending','atokenpending0000000000000000000000000000000000',null,null),
  ('a0000000-0000-0000-0000-000000000401','a0000000-0000-0000-0000-000000000302','a0000000-0000-0000-0000-000000000100','pin','approved','atokenapproved000000000000000000000000000000000','Staging A manager',now());
insert into approval_settings (id, company_id, method, is_required, auto_lock, pin_hash, pin_salt, notify_email) values
  ('a0000000-0000-0000-0000-000000000410','a0000000-0000-0000-0000-000000000100','pin',true,true,'seed-pin-hash-a','seed-pin-salt-a','x@staging.test');
insert into invoices (id, restaurant_id, company_id, invoice_number, status, subtotal, vat_amount, total) values
  ('a0000000-0000-0000-0000-000000000500','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000100','F-A-500','draft',10,0.9,10.90),
  ('a0000000-0000-0000-0000-000000000501','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000100','F-A-501','sent',20,1.8,21.80),
  ('a0000000-0000-0000-0000-000000000502','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000100','F-A-502','paid',30,2.7,32.70);
insert into invoice_lines (id, invoice_id, receipt_id, description, amount) values ('a0000000-0000-0000-0000-000000000510','a0000000-0000-0000-0000-000000000502','a0000000-0000-0000-0000-000000000302','Lunch',30.00);
insert into payments (id, invoice_id, amount, method) values ('a0000000-0000-0000-0000-000000000520','a0000000-0000-0000-0000-000000000502',32.70,'pin');
insert into documents (id, restaurant_id, type, related_table, related_id, storage_path) values
  ('a0000000-0000-0000-0000-000000000530','a0000000-0000-0000-0000-000000000001','invoice','invoices','a0000000-0000-0000-0000-000000000502','a0000000-0000-0000-0000-000000000001/invoices/a0000000-0000-0000-0000-000000000502.pdf');
insert into storage.objects (bucket_id, name) values ('documents','a0000000-0000-0000-0000-000000000001/invoices/a0000000-0000-0000-0000-000000000502.pdf');
insert into daily_closings (id, restaurant_id, closing_date, closed_by, total_revenue, business_revenue) values
  ('a0000000-0000-0000-0000-000000000600','a0000000-0000-0000-0000-000000000001',current_date - 1,'a0000000-0000-0000-0000-000000000010',100,50);
insert into activity_log (id, restaurant_id, user_id, action, target_table, target_id) values ('a0000000-0000-0000-0000-000000000610','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000010','seed activiteit','receipts','a0000000-0000-0000-0000-000000000300');
insert into domain_events (id, restaurant_id, event_type, payload, published_by) values ('a0000000-0000-0000-0000-000000000611','a0000000-0000-0000-0000-000000000001','TabOpened','{}','a0000000-0000-0000-0000-000000000010');
insert into audit_log (id, restaurant_id, table_name, record_id, action, changed_by) values ('a0000000-0000-0000-0000-000000000612','a0000000-0000-0000-0000-000000000001','receipts','a0000000-0000-0000-0000-000000000300','insert','a0000000-0000-0000-0000-000000000010');
insert into configurations (id, restaurant_id, company_id, key, value) values ('a0000000-0000-0000-0000-000000000620','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000100','required_fields','["receipt_number"]');
insert into workflow_rules (id, restaurant_id, company_id, invoice_frequency, requires_approval) values ('a0000000-0000-0000-0000-000000000621','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000100','immediate',true);
insert into integration_plugins (id, restaurant_id, plugin_type, plugin_name, plugin_version, min_core_version, is_active, config) values
  ('a0000000-0000-0000-0000-000000000630','a0000000-0000-0000-0000-000000000001','pos','TestPOS','0.0.1','1.0',false,'{"api_key":"seed-secret-a"}');
-- fase 1 (0024): ook company_codes en notifications hebben testrijen, zodat "0 rijen" iets bewijst
insert into company_codes (id, company_id, type, code) values ('a0000000-0000-0000-0000-000000000640','a0000000-0000-0000-0000-000000000100','routecode','R-1');
insert into notifications (id, restaurant_id, recipient_user_id, type, trigger_event) values
  ('a0000000-0000-0000-0000-000000000641','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000010','email','seed');

-- ===== data restaurant B =====
insert into companies (id, restaurant_id, name) values ('b0000000-0000-0000-0000-000000000100','b0000000-0000-0000-0000-000000000001','Bedrijf 1 (B)'), ('b0000000-0000-0000-0000-000000000105','b0000000-0000-0000-0000-000000000001','Bedrijf 2 (B)');
insert into departments (id, company_id, name) values ('b0000000-0000-0000-0000-000000000101','b0000000-0000-0000-0000-000000000100','Afdeling 1'), ('b0000000-0000-0000-0000-000000000106','b0000000-0000-0000-0000-000000000105','Afdeling bedrijf 2');
insert into cost_centers (id, company_id, department_id, name) values ('b0000000-0000-0000-0000-000000000102','b0000000-0000-0000-0000-000000000100','b0000000-0000-0000-0000-000000000101','Kostenplaats 1');
insert into projects (id, company_id, name) values ('b0000000-0000-0000-0000-000000000103','b0000000-0000-0000-0000-000000000100','Project 1');
insert into contacts (id, company_id, full_name) values ('b0000000-0000-0000-0000-000000000104','b0000000-0000-0000-0000-000000000100','Contact 1');
insert into open_tabs (id, restaurant_id, company_id, department_id, cost_center_id, project_id, contact_id, status, closed_at) values
  ('b0000000-0000-0000-0000-000000000200','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000100','b0000000-0000-0000-0000-000000000101','b0000000-0000-0000-0000-000000000102','b0000000-0000-0000-0000-000000000103','b0000000-0000-0000-0000-000000000104','open',null),
  ('b0000000-0000-0000-0000-000000000201','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000100',null,null,null,null,'closed',now()),
  ('b0000000-0000-0000-0000-000000000202','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000100',null,null,null,null,'invoiced',now()),
  ('b0000000-0000-0000-0000-000000000203','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000100',null,null,null,null,'closed',now()),
  ('b0000000-0000-0000-0000-000000000204','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000100',null,null,null,null,'open',null);
insert into receipts (id, restaurant_id, open_tab_id, receipt_number, status, total, receipt_date, created_by) values
  ('b0000000-0000-0000-0000-000000000300','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000200','B-300','linked',10.00,current_date,'b0000000-0000-0000-0000-000000000013'),
  ('b0000000-0000-0000-0000-000000000301','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000200','B-301','pending_approval',20.00,current_date,'b0000000-0000-0000-0000-000000000013'),
  ('b0000000-0000-0000-0000-000000000302','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000202','B-302','locked',30.00,current_date,'b0000000-0000-0000-0000-000000000013'),
  ('b0000000-0000-0000-0000-000000000303','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000201','B-303','approved',40.00,current_date,'b0000000-0000-0000-0000-000000000013');
insert into receipt_lines (id, receipt_id, description, quantity, unit_price, vat_rate, line_total) values
  ('b0000000-0000-0000-0000-000000000310','b0000000-0000-0000-0000-000000000300','Koffie',2,5.00,9,10.00), ('b0000000-0000-0000-0000-000000000311','b0000000-0000-0000-0000-000000000302','Lunch',1,30.00,9,30.00);
insert into approvals (id, receipt_id, company_id, method, status, verification_code, approved_by, approved_at) values
  ('b0000000-0000-0000-0000-000000000400','b0000000-0000-0000-0000-000000000301','b0000000-0000-0000-0000-000000000100','qr','pending','btokenpending0000000000000000000000000000000000',null,null),
  ('b0000000-0000-0000-0000-000000000401','b0000000-0000-0000-0000-000000000302','b0000000-0000-0000-0000-000000000100','pin','approved','btokenapproved000000000000000000000000000000000','Staging B manager',now());
insert into approval_settings (id, company_id, method, is_required, auto_lock, pin_hash, pin_salt, notify_email) values
  ('b0000000-0000-0000-0000-000000000410','b0000000-0000-0000-0000-000000000100','pin',true,true,'seed-pin-hash-b','seed-pin-salt-b','x@staging.test');
insert into invoices (id, restaurant_id, company_id, invoice_number, status, subtotal, vat_amount, total) values
  ('b0000000-0000-0000-0000-000000000500','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000100','F-B-500','draft',10,0.9,10.90),
  ('b0000000-0000-0000-0000-000000000501','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000100','F-B-501','sent',20,1.8,21.80),
  ('b0000000-0000-0000-0000-000000000502','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000100','F-B-502','paid',30,2.7,32.70);
insert into invoice_lines (id, invoice_id, receipt_id, description, amount) values ('b0000000-0000-0000-0000-000000000510','b0000000-0000-0000-0000-000000000502','b0000000-0000-0000-0000-000000000302','Lunch',30.00);
insert into payments (id, invoice_id, amount, method) values ('b0000000-0000-0000-0000-000000000520','b0000000-0000-0000-0000-000000000502',32.70,'pin');
insert into documents (id, restaurant_id, type, related_table, related_id, storage_path) values
  ('b0000000-0000-0000-0000-000000000530','b0000000-0000-0000-0000-000000000001','invoice','invoices','b0000000-0000-0000-0000-000000000502','b0000000-0000-0000-0000-000000000001/invoices/b0000000-0000-0000-0000-000000000502.pdf');
insert into storage.objects (bucket_id, name) values ('documents','b0000000-0000-0000-0000-000000000001/invoices/b0000000-0000-0000-0000-000000000502.pdf');
insert into daily_closings (id, restaurant_id, closing_date, closed_by, total_revenue, business_revenue) values
  ('b0000000-0000-0000-0000-000000000600','b0000000-0000-0000-0000-000000000001',current_date - 1,'b0000000-0000-0000-0000-000000000010',100,50);
insert into activity_log (id, restaurant_id, user_id, action, target_table, target_id) values ('b0000000-0000-0000-0000-000000000610','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000010','seed activiteit','receipts','b0000000-0000-0000-0000-000000000300');
insert into domain_events (id, restaurant_id, event_type, payload, published_by) values ('b0000000-0000-0000-0000-000000000611','b0000000-0000-0000-0000-000000000001','TabOpened','{}','b0000000-0000-0000-0000-000000000010');
insert into audit_log (id, restaurant_id, table_name, record_id, action, changed_by) values ('b0000000-0000-0000-0000-000000000612','b0000000-0000-0000-0000-000000000001','receipts','b0000000-0000-0000-0000-000000000300','insert','b0000000-0000-0000-0000-000000000010');
insert into configurations (id, restaurant_id, company_id, key, value) values ('b0000000-0000-0000-0000-000000000620','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000100','required_fields','["receipt_number"]');
insert into workflow_rules (id, restaurant_id, company_id, invoice_frequency, requires_approval) values ('b0000000-0000-0000-0000-000000000621','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000100','immediate',true);
insert into integration_plugins (id, restaurant_id, plugin_type, plugin_name, plugin_version, min_core_version, is_active, config) values
  ('b0000000-0000-0000-0000-000000000630','b0000000-0000-0000-0000-000000000001','pos','TestPOS','0.0.1','1.0',false,'{"api_key":"seed-secret-b"}');
-- fase 1 (0024): ook company_codes en notifications hebben testrijen, zodat "0 rijen" iets bewijst
insert into company_codes (id, company_id, type, code) values ('b0000000-0000-0000-0000-000000000640','b0000000-0000-0000-0000-000000000100','routecode','R-1');
insert into notifications (id, restaurant_id, recipient_user_id, type, trigger_event) values
  ('b0000000-0000-0000-0000-000000000641','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000010','email','seed');
