-- ============================================================
-- Migratie 0011: Fase C — notify_email voor Approval Engine
-- ============================================================

alter table approval_settings add column if not exists notify_email text;
