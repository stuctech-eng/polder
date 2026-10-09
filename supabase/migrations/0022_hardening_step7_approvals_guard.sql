-- ============================================================
-- Migratie 0022 — SECURITY HARDENING STAP 7 (vervolg): aanscherping approvals_guard()
-- Vereist 0021 (approvals_guard + trigger). Geen app-wijziging nodig. Bestaande data wordt niet gewijzigd.
--
--  Twee kleine toevoegingen aan approvals_guard(); alles anders (trigger, rechten, DELETE-tak, bestaande regels) blijft gelijk:
--   1. INSERT: geen nieuwe goedkeuringsregel als de bon al 'approved' of 'locked' is.
--   2. UPDATE: bij een bon die 'approved' of 'locked' is kan een goedkeuringsregel niet meer van pending naar
--      'rejected' of 'expired'. De legitieme overgang pending -> approved blijft toegestaan (goedkeur-route en publieke link
--      zetten eerst de bon op approved/locked en daarna de regel op approved).
--  Beide controles staan VOOR de rechtencontrole en gelden voor iedereen, ook service_role en postgres (geen bypass).
--  Reden: de goedkeuringsgeschiedenis van een afgehandelde bon mag niet meer vervuild worden; basis voor de
--  factuurblokkade van afgewezen bonnen (plan 7b).
-- Rollback: supabase/rollbacks/0022_rollback.sql
-- ============================================================
begin;

do $$
begin
  if to_regprocedure('public.approvals_guard()') is null then
    raise exception 'Stap 7 (migratie 0021) ontbreekt: draai die eerst';
  end if;
  if (select count(*) from pg_trigger
       where not tgisinternal and tgenabled = 'O' and tgname = 'approvals_guard'
         and tgrelid = 'public.approvals'::regclass) <> 1 then
    raise exception 'Trigger approvals_guard ontbreekt of staat niet aan: eerst beoordelen';
  end if;
  if exists (select 1 from pg_trigger where not tgisinternal and tgname = 'approvals_guard'
               and tgrelid <> 'public.approvals'::regclass) then
    raise exception 'Onverwachte trigger met de naam approvals_guard: eerst beoordelen';
  end if;
  -- bestaande data: een afgehandelde bon met een afwijzing/verlopen regel zonder goedkeuring wordt gemeld, niet aangepast
  if exists (select 1 from public.receipts r
              where r.status in ('approved', 'locked')
                and exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status in ('rejected', 'expired'))
                and not exists (select 1 from public.approvals a where a.receipt_id = r.id and a.status = 'approved')) then
    raise exception 'Bestaande afgehandelde bon met afwijzing maar zonder goedkeuring: eerst beoordelen (geen data gewijzigd)';
  end if;
end $$;

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
    -- NIEUW (0022): een goedgekeurde of vergrendelde bon krijgt geen nieuwe goedkeuringsregel meer
    if exists (select 1 from public.receipts r where r.id = new.receipt_id and r.status in ('approved', 'locked')) then
      raise exception 'Een goedgekeurde of vergrendelde bon kan geen nieuwe goedkeuring meer krijgen' using errcode = 'check_violation';
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
  -- NIEUW (0022): bij een goedgekeurde of vergrendelde bon blijft alleen pending -> approved mogelijk
  if new.status in ('rejected', 'expired')
     and exists (select 1 from public.receipts r where r.id = new.receipt_id and r.status in ('approved', 'locked')) then
    raise exception 'Een goedkeuring van een goedgekeurde of vergrendelde bon kan niet meer worden afgewezen of verlopen' using errcode = 'check_violation';
  end if;
  if not (public.has_perm('APPROVE_RECEIPTS') or current_user = 'service_role') then
    raise exception 'Geen recht om een goedkeuring af te handelen' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

revoke all on function public.approvals_guard() from public, anon, authenticated, service_role;

commit;
