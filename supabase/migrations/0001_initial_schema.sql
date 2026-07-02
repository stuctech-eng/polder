-- ============================================================
-- Restaurant Business Accounting Platform — Fase 1 schema
-- Bron van waarheid: PostgreSQL (governance-principe 6.2)
-- ============================================================

create extension if not exists "uuid-ossp";

-- ------------------------------------------------------------
-- TENANT ROOT
-- ------------------------------------------------------------
create table restaurants (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table users (
  id uuid primary key references auth.users(id) on delete cascade,
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  full_name text not null,
  role text not null check (role in ('owner','manager','administratie','bediening','keuken')),
  two_factor_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- BEDRIJVENBEHEER (Fase 1 — eerste module)
-- ------------------------------------------------------------
create table companies (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  name text not null,
  address text,
  vat_number text,
  coc_number text,
  invoice_email text,
  payment_term_days integer not null default 30,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table contacts (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references companies(id) on delete cascade,
  full_name text not null,
  email text,
  phone text,
  created_at timestamptz not null default now()
);

create table departments (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table cost_centers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references companies(id) on delete cascade,
  department_id uuid references departments(id) on delete set null,
  name text not null,
  code text,
  created_at timestamptz not null default now()
);

create table projects (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null,
  code text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- OPEN REKENINGEN
-- ------------------------------------------------------------
create table open_tabs (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  company_id uuid references companies(id),
  department_id uuid references departments(id),
  cost_center_id uuid references cost_centers(id),
  project_id uuid references projects(id),
  contact_id uuid references contacts(id),
  table_number text,
  guest_count integer,
  status text not null default 'open' check (status in ('open','closed','invoiced')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz
);

-- ------------------------------------------------------------
-- BONNEN (Receipt Engine — Fase 1: alleen handmatige invoer)
-- ------------------------------------------------------------
create table receipts (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  open_tab_id uuid references open_tabs(id),
  receipt_number text,
  source text not null default 'manual' check (source in ('api','import','qr','ocr','manual')),
  status text not null default 'draft' check (status in ('draft','validated','linked')),
  subtotal numeric(12,2),
  vat_amount numeric(12,2),
  total numeric(12,2),
  receipt_date date,
  scan_url text,
  notes text,
  created_by uuid references users(id),
  created_at timestamptz not null default now()
);

create table receipt_lines (
  id uuid primary key default uuid_generate_v4(),
  receipt_id uuid not null references receipts(id) on delete cascade,
  description text not null,
  quantity numeric(10,2) not null default 1,
  unit_price numeric(12,2) not null,
  vat_rate numeric(5,2) not null default 0,
  line_total numeric(12,2) not null
);

-- ------------------------------------------------------------
-- FACTURATIE & DOCUMENTEN (generiek Document Engine)
-- ------------------------------------------------------------
create table invoices (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  company_id uuid not null references companies(id),
  invoice_number text not null,
  status text not null default 'draft' check (status in ('draft','sent','paid','overdue')),
  subtotal numeric(12,2) not null default 0,
  vat_amount numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  issued_at date,
  due_at date,
  created_at timestamptz not null default now()
);

create table invoice_lines (
  id uuid primary key default uuid_generate_v4(),
  invoice_id uuid not null references invoices(id) on delete cascade,
  receipt_id uuid references receipts(id),
  description text not null,
  amount numeric(12,2) not null
);

create table documents (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  type text not null check (type in ('invoice','credit_note','quote','packing_slip','report_export')),
  related_table text not null,
  related_id uuid not null,
  storage_path text not null,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- WORKFLOW ENGINE & CONFIGURATIELAAG (config-driven, governance 6.1/6.3)
-- ------------------------------------------------------------
create table workflow_rules (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  company_id uuid references companies(id),
  invoice_frequency text not null default 'immediate' check (invoice_frequency in ('immediate','weekly','monthly','per_project')),
  requires_approval boolean not null default false,
  created_at timestamptz not null default now()
);

create table configurations (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  company_id uuid references companies(id),
  key text not null,
  value jsonb not null,
  created_at timestamptz not null default now(),
  unique (restaurant_id, company_id, key)
);

-- ------------------------------------------------------------
-- BETALINGEN
-- ------------------------------------------------------------
create table payments (
  id uuid primary key default uuid_generate_v4(),
  invoice_id uuid not null references invoices(id) on delete cascade,
  amount numeric(12,2) not null,
  paid_at timestamptz not null default now(),
  method text
);

-- ------------------------------------------------------------
-- NOTIFICATIES
-- ------------------------------------------------------------
create table notifications (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  recipient_user_id uuid references users(id),
  type text not null,
  status text not null default 'pending' check (status in ('pending','sent','failed')),
  trigger_event text not null,
  payload jsonb,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- EVENT BUS — domain_events (governance 6.1: interne eventbus, stabiele contracten)
-- ------------------------------------------------------------
create table domain_events (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  event_type text not null, -- bv. 'ReceiptLinked', 'InvoiceGenerated', 'PaymentReceived'
  payload jsonb not null,
  published_by uuid references users(id),
  created_at timestamptz not null default now()
);
create index idx_domain_events_type on domain_events(event_type);
create index idx_domain_events_restaurant on domain_events(restaurant_id);

-- ------------------------------------------------------------
-- AUDIT & ACTIVITY ENGINE (verplicht vanaf Fase 1)
-- ------------------------------------------------------------
create table audit_log (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  table_name text not null,
  record_id uuid not null,
  action text not null check (action in ('insert','update','delete')),
  old_data jsonb,
  new_data jsonb,
  changed_by uuid references users(id),
  changed_at timestamptz not null default now()
);

create table activity_log (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  user_id uuid references users(id),
  action text not null, -- bv. "koppelde bon 15421", "wijzigde kostenplaats"
  target_table text,
  target_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- PLUGIN-VERSIEBEHEER (governance 6.3 — voorbereiding op Fase 2)
-- ------------------------------------------------------------
create table integration_plugins (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  plugin_type text not null check (plugin_type in ('pos','accounting','payment','reservation','loyalty')),
  plugin_name text not null,
  plugin_version text not null,
  min_core_version text not null,
  is_active boolean not null default false,
  config jsonb,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- ROW LEVEL SECURITY (multi-tenant isolatie — activeren per tabel)
-- ------------------------------------------------------------
alter table companies enable row level security;
alter table open_tabs enable row level security;
alter table receipts enable row level security;
alter table invoices enable row level security;
alter table domain_events enable row level security;
alter table audit_log enable row level security;
alter table activity_log enable row level security;

-- Voorbeeldpolicy (per tabel te herhalen): gebruiker ziet alleen data van eigen restaurant
create policy "tenant isolation companies" on companies
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );
