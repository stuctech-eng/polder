-- ============================================================
-- Migratie 0007: Fase B — Approval Engine schema-uitbreiding
-- Vult de kleine gaten uit Fase A (migratie 0006) aan.
-- ============================================================

alter table approval_settings add column if not exists pin_hash text;
alter table approval_settings add column if not exists pin_salt text;

alter table approvals add column if not exists requested_at timestamptz not null default now();
alter table approvals add column if not exists metadata jsonb;

alter table approvals drop constraint if exists approvals_status_check;
alter table approvals add constraint approvals_status_check
  check (status in ('pending', 'approved', 'rejected', 'expired'));
