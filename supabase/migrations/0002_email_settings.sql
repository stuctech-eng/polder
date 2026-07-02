-- ============================================================
-- Migratie 0002: Email Engine (v1.2)
-- Provider-onafhankelijke e-mailinstellingen per restaurant
-- Draai deze migratie in de Supabase SQL Editor voordat je Resend koppelt.
-- ============================================================

create table email_settings (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  provider text not null default 'resend',
  sender_name text,
  sender_email text,
  reply_to text,
  custom_domain text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurant_id)
);

alter table email_settings enable row level security;

create policy "tenant isolation email_settings" on email_settings
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );
