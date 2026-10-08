-- ============================================================
-- Migratie 0021 — SECURITY HARDENING STAP 7: H4a (open_tabs, receipts, receipt_lines, approvals)
-- Vereist 0015 (helpers) en 0019 (cross-reference triggers). Geen app-wijziging nodig.
--
--  1. Policies: "for all, alleen restaurant" vervangen door per bewerking + per rol (has_perm):
--       open_tabs     MANAGE_OPEN_TABS  (insert alleen status 'open')
--       receipts      MANAGE_RECEIPTS   (insert alleen status 'draft' of 'linked')
--       receipt_lines MANAGE_RECEIPTS   (alleen lezen + toevoegen; via de bon in het eigen restaurant)
--       approvals     lezen/toevoegen MANAGE_RECEIPTS (toevoegen alleen als 'pending'); wijzigen APPROVE_RECEIPTS; geen delete
--  2. Vangnet-triggers (gelden voor IEDEREEN, ook service-role en postgres; GEEN algemene service-role-bypass):
--       receipts_guard, receipt_lines_guard, open_tabs_guard, approvals_guard.
--     Enige service-role-uitzondering: de publieke goedkeuringslink mag precies
--       bon pending_approval -> locked | linked   en   approval pending -> approved | rejected | expired.
--     Een delete via ON DELETE CASCADE (bon -> regels/goedkeuringen, restaurant -> alles) blijft mogelijk.
--  3. Bestaande data wordt niet gewijzigd. Statusregels volgen wat de app al doet (zie docs/architecture.md 13.15).
-- Niet in deze stap: invoices/payments/documents (H4b), logs, D1-D9, storage, grants (stap 11).
-- Rollback: supabase/rollbacks/0021_rollback.sql
-- ============================================================
begin;

do $$
begin
  if to_regprocedure('public.has_perm(text)') is null or to_regprocedure('public.my_restaurant_id()') is null then
    raise exception 'Stap 1 (migratie 0015) ontbreekt: draai die eerst';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'xref_receipts' and not tgisinternal) then
    raise exception 'Stap 5 (migratie 0019) ontbreekt: draai die eerst';
  end if;
  if exists (select 1 from pg_policies
             where schemaname = 'public' and tablename in ('open_tabs', 'receipts', 'receipt_lines', 'approvals')
               and policyname not in ('tenant isolation open_tabs', 'tenant isolation receipts',
                                      'tenant isolation receipt_lines', 'tenant isolation approvals',
                                      'open_tabs select', 'open_tabs insert', 'open_tabs update', 'open_tabs delete',
                                      'receipts select', 'receipts insert', 'receipts update', 'receipts delete',
                                      'receipt_lines select', 'receipt_lines insert',
                                      'approvals select', 'approvals insert', 'approvals update')) then
    raise exception 'Onverwachte policy op open_tabs/receipts/receipt_lines/approvals: eerst beoordelen';
  end if;
  if exists (select 1 from pg_trigger
             where not tgisinternal and tgname in ('receipts_guard', 'receipt_lines_guard', 'open_tabs_guard', 'approvals_guard')
               and not (tgrelid in ('public.receipts'::regclass, 'public.receipt_lines'::regclass, 'public.open_tabs'::regclass, 'public.approvals'::regclass))) then
    raise exception 'Onverwachte trigger met een guard-naam: eerst beoordelen';
  end if;
end $$;

-- ------------------------------------------------------------
-- 1. POLICIES
-- ------------------------------------------------------------
-- open_tabs
drop policy if exists "tenant isolation open_tabs" on public.open_tabs;
drop policy if exists "open_tabs select" on public.open_tabs;
drop policy if exists "open_tabs insert" on public.open_tabs;
drop policy if exists "open_tabs update" on public.open_tabs;
drop policy if exists "open_tabs delete" on public.open_tabs;
create policy "open_tabs select" on public.open_tabs for select to authenticated
  using (restaurant_id = public.my_restaurant_id() and public.has_perm('MANAGE_OPEN_TABS'));
create policy "open_tabs insert" on public.open_tabs for insert to authenticated
  with check (restaurant_id = public.my_restaurant_id() and public.has_perm('MANAGE_OPEN_TABS') and status = 'open');
create policy "open_tabs update" on public.open_tabs for update to authenticated
  using (restaurant_id = public.my_restaurant_id() and public.has_perm('MANAGE_OPEN_TABS'))
  with check (restaurant_id = public.my_restaurant_id() and public.has_perm('MANAGE_OPEN_TABS'));
create policy "open_tabs delete" on public.open_tabs for delete to authenticated
  using (restaurant_id = public.my_restaurant_id() and public.has_perm('MANAGE_OPEN_TABS'));

-- receipts
drop policy if exists "tenant isolation receipts" on public.receipts;
drop policy if exists "receipts select" on public.receipts;
drop policy if exists "receipts insert" on public.receipts;
drop policy if exists "receipts update" on public.receipts;
drop policy if exists "receipts delete" on public.receipts;
create policy "receipts select" on public.receipts for select to authenticated
  using (restaurant_id = public.my_restaurant_id() and public.has_perm('MANAGE_RECEIPTS'));
create policy "receipts insert" on public.receipts for insert to authenticated
  with check (restaurant_id = public.my_restaurant_id() and public.has_perm('MANAGE_RECEIPTS') and status in ('draft', 'linked'));
create policy "receipts update" on public.receipts for update to authenticated
  using (restaurant_id = public.my_restaurant_id() and public.has_perm('MANAGE_RECEIPTS'))
  with check (restaurant_id = public.my_restaurant_id() and public.has_perm('MANAGE_RECEIPTS'));
create policy "receipts delete" on public.receipts for delete to authenticated
  using (restaurant_id = public.my_restaurant_id() and public.has_perm('MANAGE_RECEIPTS'));

-- receipt_lines: alleen lezen en toevoegen (de app wijzigt of verwijdert nooit direct een regel)
drop policy if exists "tenant isolation receipt_lines" on public.receipt_lines;
drop policy if exists "receipt_lines select" on public.receipt_lines;
drop policy if exists "receipt_lines insert" on public.receipt_lines;
create policy "receipt_lines select" on public.receipt_lines for select to authenticated
  using (public.has_perm('MANAGE_RECEIPTS')
         and exists (select 1 from public.receipts r where r.id = receipt_lines.receipt_id and r.restaurant_id = public.my_restaurant_id()));
create policy "receipt_lines insert" on public.receipt_lines for insert to authenticated
  with check (public.has_perm('MANAGE_RECEIPTS')
              and exists (select 1 from public.receipts r where r.id = receipt_lines.receipt_id and r.restaurant_id = public.my_restaurant_id()));

-- approvals: lezen en toevoegen = bonnenbeheer; wijzigen (goedkeuren) = APPROVE_RECEIPTS; geen delete-policy
drop policy if exists "tenant isolation approvals" on public.approvals;
drop policy if exists "approvals select" on public.approvals;
drop policy if exists "approvals insert" on public.approvals;
drop policy if exists "approvals update" on public.approvals;
create policy "approvals select" on public.approvals for select to authenticated
  using (public.has_perm('MANAGE_RECEIPTS')
         and exists (select 1 from public.receipts r where r.id = approvals.receipt_id and r.restaurant_id = public.my_restaurant_id()));
create policy "approvals insert" on public.approvals for insert to authenticated
  with check (public.has_perm('MANAGE_RECEIPTS') and status = 'pending'
              and exists (select 1 from public.receipts r where r.id = approvals.receipt_id and r.restaurant_id = public.my_restaurant_id())
              and exists (select 1 from public.companies c where c.id = approvals.company_id and c.restaurant_id = public.my_restaurant_id()));
create policy "approvals update" on public.approvals for update to authenticated
  using (public.has_perm('APPROVE_RECEIPTS')
         and exists (select 1 from public.receipts r where r.id = approvals.receipt_id and r.restaurant_id = public.my_restaurant_id()))
  with check (public.has_perm('APPROVE_RECEIPTS')
              and exists (select 1 from public.receipts r where r.id = approvals.receipt_id and r.restaurant_id = public.my_restaurant_id()));

-- ------------------------------------------------------------
-- 2. TRIGGERS (SECURITY INVOKER: de uitvoerende rol is zichtbaar via current_user)
--    'service_role' = de publieke goedkeuringslink (server-side). Een cascade-delete herkennen we aan: genest in een andere trigger
--    (pg_trigger_depth() > 1) én het restaurant bestaat niet meer; dat is niet te vervalsen door een gebruiker.
-- ------------------------------------------------------------
create or replace function public.receipts_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare
  v_tab_status text;
  v_can_approve boolean := public.has_perm('APPROVE_RECEIPTS');
  v_public_link boolean := current_user = 'service_role';
begin
  if tg_op = 'DELETE' then
    -- cascade bij verwijderen van het hele restaurant: de delete komt uit een ander (RI-)trigger en het restaurant is al weg
    if pg_trigger_depth() > 1
       and not exists (select 1 from public.restaurants where id = old.restaurant_id) then
      return old;
    end if;
    if old.status in ('pending_approval', 'approved', 'locked') then
      raise exception 'Een bon met status % kan niet worden verwijderd', old.status using errcode = 'check_violation';
    end if;
    if old.open_tab_id is not null then
      select status into v_tab_status from public.open_tabs where id = old.open_tab_id;
      if v_tab_status = 'invoiced' then
        raise exception 'Een bon van een gefactureerde rekening kan niet worden verwijderd' using errcode = 'check_violation';
      end if;
    end if;
    return old;
  end if;

  if tg_op = 'INSERT' then
    if new.status not in ('draft', 'linked') then
      raise exception 'Een nieuwe bon moet status draft of linked hebben (niet %)', new.status using errcode = 'check_violation';
    end if;
    if new.open_tab_id is not null then
      select status into v_tab_status from public.open_tabs where id = new.open_tab_id;
      if v_tab_status is distinct from 'open' then
        raise exception 'Een bon kan alleen aan een open rekening worden gekoppeld' using errcode = 'check_violation';
      end if;
    end if;
    return new;
  end if;

  -- UPDATE
  if new.id is distinct from old.id then
    raise exception 'receipts.id is onveranderlijk' using errcode = 'check_violation';
  end if;

  -- bon van een gefactureerde rekening: onveranderlijk
  if old.open_tab_id is not null and to_jsonb(new) is distinct from to_jsonb(old) then
    select status into v_tab_status from public.open_tabs where id = old.open_tab_id;
    if v_tab_status = 'invoiced' then
      raise exception 'Een bon van een gefactureerde rekening kan niet meer worden gewijzigd' using errcode = 'check_violation';
    end if;
  end if;

  -- verhuizen naar een andere rekening: alleen naar een open rekening
  if new.open_tab_id is distinct from old.open_tab_id and new.open_tab_id is not null then
    select status into v_tab_status from public.open_tabs where id = new.open_tab_id;
    if v_tab_status is distinct from 'open' then
      raise exception 'Een bon kan alleen aan een open rekening worden gekoppeld' using errcode = 'check_violation';
    end if;
  end if;

  if new.status is distinct from old.status then
    if new.status = 'pending_approval' then
      if old.status not in ('draft', 'linked') then
        raise exception 'Alleen een bon met status draft of linked kan ter goedkeuring worden aangeboden' using errcode = 'check_violation';
      end if;
      if not public.has_perm('MANAGE_RECEIPTS') then
        raise exception 'Geen recht om een bon ter goedkeuring aan te bieden' using errcode = 'insufficient_privilege';
      end if;
    elsif new.status in ('approved', 'locked') then
      if not ((old.status = 'pending_approval') or (old.status = 'approved' and new.status = 'locked')) then
        raise exception 'Ongeldige statusovergang van bon: % -> %', old.status, new.status using errcode = 'check_violation';
      end if;
      if not (v_can_approve or (v_public_link and old.status = 'pending_approval' and new.status = 'locked')) then
        raise exception 'Geen recht om een bon goed te keuren of te vergrendelen' using errcode = 'insufficient_privilege';
      end if;
    elsif old.status in ('pending_approval', 'approved', 'locked') then
      -- uit een beschermde status: alleen afwijzing pending_approval -> linked
      if not (old.status = 'pending_approval' and new.status = 'linked') then
        raise exception 'Ongeldige statusovergang van bon: % -> %', old.status, new.status using errcode = 'check_violation';
      end if;
      if not (v_can_approve or v_public_link) then
        raise exception 'Geen recht om een bon af te wijzen' using errcode = 'insufficient_privilege';
      end if;
    end if;
  end if;

  -- in een beschermde status is alleen de status zelf te wijzigen; alle andere velden zijn vast
  if old.status in ('pending_approval', 'approved', 'locked')
     and (to_jsonb(new) - 'status') is distinct from (to_jsonb(old) - 'status') then
    raise exception 'Een bon met status % kan niet worden gewijzigd', old.status using errcode = 'check_violation';
  end if;

  return new;
end $$;

create or replace function public.receipt_lines_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare
  v_status text;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    select status into v_status from public.receipts where id = old.receipt_id;
    if v_status is null then
      if tg_op = 'DELETE' then return old; end if;       -- ouder is weg (cascade)
    elsif v_status not in ('draft', 'linked') then
      raise exception 'Regels van een bon met status % kunnen niet worden gewijzigd', v_status using errcode = 'check_violation';
    end if;
    if tg_op = 'DELETE' then return old; end if;
  end if;
  select status into v_status from public.receipts where id = new.receipt_id;
  if v_status is null or v_status not in ('draft', 'linked') then
    raise exception 'Regels kunnen alleen worden toegevoegd of gewijzigd bij een bon met status draft of linked' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create or replace function public.open_tabs_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() > 1
       and not exists (select 1 from public.restaurants where id = old.restaurant_id) then
      return old;
    end if;
    if old.status <> 'open' then
      raise exception 'Alleen een open rekening kan worden verwijderd' using errcode = 'check_violation';
    end if;
    return old;
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'open' then
      raise exception 'Een nieuwe rekening moet status open hebben' using errcode = 'check_violation';
    end if;
    return new;
  end if;

  -- UPDATE
  if old.status = 'invoiced' and to_jsonb(new) is distinct from to_jsonb(old) then
    raise exception 'Een gefactureerde rekening is onveranderlijk' using errcode = 'check_violation';
  end if;
  if new.status is distinct from old.status then
    if old.status = 'open' and new.status = 'closed' then
      if not public.has_perm('MANAGE_OPEN_TABS') then
        raise exception 'Geen recht om een rekening te sluiten' using errcode = 'insufficient_privilege';
      end if;
    elsif old.status = 'closed' and new.status = 'invoiced' then
      if not public.has_perm('MANAGE_INVOICES') then
        raise exception 'Geen recht om een rekening te factureren' using errcode = 'insufficient_privilege';
      end if;
    else
      raise exception 'Ongeldige statusovergang van rekening: % -> %', old.status, new.status using errcode = 'check_violation';
    end if;
  end if;
  return new;
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

drop trigger if exists receipts_guard on public.receipts;
create trigger receipts_guard before insert or update or delete on public.receipts
  for each row execute function public.receipts_guard();
drop trigger if exists receipt_lines_guard on public.receipt_lines;
create trigger receipt_lines_guard before insert or update or delete on public.receipt_lines
  for each row execute function public.receipt_lines_guard();
drop trigger if exists open_tabs_guard on public.open_tabs;
create trigger open_tabs_guard before insert or update or delete on public.open_tabs
  for each row execute function public.open_tabs_guard();
drop trigger if exists approvals_guard on public.approvals;
create trigger approvals_guard before insert or update or delete on public.approvals
  for each row execute function public.approvals_guard();

revoke all on function public.receipts_guard()      from public, anon, authenticated, service_role;
revoke all on function public.receipt_lines_guard() from public, anon, authenticated, service_role;
revoke all on function public.open_tabs_guard()     from public, anon, authenticated, service_role;
revoke all on function public.approvals_guard()     from public, anon, authenticated, service_role;

commit;
