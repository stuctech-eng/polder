-- ============================================================
-- Rollback van migratie 0022: approvals_guard() terug naar exact de versie van 0021.
-- Trigger, rechten en data blijven ongemoeid.
-- ============================================================
begin;

create or replace function public.approvals_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    if exists (select 1 from public.receipts where id = old.receipt_id) then
      raise exception 'Een goedkeuring kan niet worden verwijderd' using errcode = 'insufficient_privilege';
    end if;
    return old;                                           -- bon is weg (cascade)
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'pending' or new.approved_by is not null or new.approved_at is not null or new.signature_data is not null then
      raise exception 'Een nieuwe goedkeuring moet status pending hebben en leeg zijn' using errcode = 'check_violation';
    end if;
    return new;
  end if;

  -- UPDATE
  if to_jsonb(new) = to_jsonb(old) then return new; end if;
  if old.status <> 'pending' then
    raise exception 'Een afgehandelde goedkeuring (%) is onveranderlijk', old.status using errcode = 'check_violation';
  end if;
  if (to_jsonb(new) - 'status' - 'approved_by' - 'approved_at' - 'metadata' - 'signature_data')
     is distinct from (to_jsonb(old) - 'status' - 'approved_by' - 'approved_at' - 'metadata' - 'signature_data') then
    raise exception 'Bon, bedrijf, methode, code en aanvraagtijd van een goedkeuring zijn onveranderlijk' using errcode = 'check_violation';
  end if;
  if new.status not in ('approved', 'rejected', 'expired') then
    raise exception 'Een goedkeuring kan alleen van pending naar approved, rejected of expired' using errcode = 'check_violation';
  end if;
  if not (public.has_perm('APPROVE_RECEIPTS') or current_user = 'service_role') then
    raise exception 'Geen recht om een goedkeuring af te handelen' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

revoke all on function public.approvals_guard() from public, anon, authenticated, service_role;

commit;
