-- ============================================================
-- Migratie 0006: Fase A — Approval Engine schema-fundament
-- Bedrijfsreferenties (company_codes) + statusworkflow-voorbereiding
-- Additief: bestaand Fase 1-gedrag blijft volledig ongewijzigd.
-- ============================================================

-- ------------------------------------------------------------
-- BEDRIJFSREFERENTIES (generiek, geen tabel per codetype)
-- ------------------------------------------------------------
create table company_codes (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references companies(id) on delete cascade,
  type text not null, -- vrije string: 'routecode', 'wbs_wbf', 'budgetcode', enz.
  code text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_company_codes_company on company_codes(company_id);
create index idx_company_codes_type on company_codes(type);

alter table company_codes enable row level security;
create policy "tenant isolation company_codes" on company_codes
  for all using (
    company_id in (
      select c.id from companies c
      where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

-- ------------------------------------------------------------
-- STATUSWORKFLOW-UITBREIDING (additief, geen bestaande waarden verwijderd)
-- ------------------------------------------------------------
alter table receipts drop constraint if exists receipts_status_check;
alter table receipts add constraint receipts_status_check
  check (status in ('draft', 'validated', 'linked', 'submitted', 'pending_approval', 'approved', 'locked'));

-- ------------------------------------------------------------
-- APPROVAL ENGINE — schema klaargezet (Fase B activeert dit pas)
-- ------------------------------------------------------------
create table approval_settings (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references companies(id) on delete cascade,
  method text check (method in ('pin', 'email', 'qr', 'signature', 'restaurant_confirms')),
  is_required boolean not null default false,
  auto_lock boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id)
);

alter table approval_settings enable row level security;
create policy "tenant isolation approval_settings" on approval_settings
  for all using (
    company_id in (
      select c.id from companies c
      where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

create table approvals (
  id uuid primary key default uuid_generate_v4(),
  receipt_id uuid not null references receipts(id) on delete cascade,
  company_id uuid not null references companies(id),
  method text not null,
  approved_by text,
  approved_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  signature_data text,
  verification_code text,
  created_at timestamptz not null default now()
);

alter table approvals enable row level security;
create policy "tenant isolation approvals" on approvals
  for all using (
    company_id in (
      select c.id from companies c
      where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );
