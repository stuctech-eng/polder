-- ============================================================
-- Migratie 0010: Daily Closing Engine
-- ============================================================

create table daily_closings (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  closing_date date not null,
  closed_by uuid references users(id),
  closed_at timestamptz not null default now(),
  total_revenue numeric(12,2) not null default 0,
  business_revenue numeric(12,2) not null default 0,
  notes text,
  reopened_at timestamptz,
  reopened_by uuid references users(id),
  created_at timestamptz not null default now(),
  unique (restaurant_id, closing_date)
);

alter table daily_closings enable row level security;
create policy "tenant isolation daily_closings" on daily_closings
  for all using (
    restaurant_id = my_restaurant_id()
  );
