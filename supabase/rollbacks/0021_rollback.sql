-- ============================================================
-- Rollback van migratie 0021 (Stap 7, H4a): zet de toestand van vóór stap 7 terug.
-- Triggers en functies weg; de vier oorspronkelijke "for all"-policies (0003 / 0006) terug. Data blijft ongemoeid.
-- Let op: de eerdere app-versie werkt direct weer; geen app-rollback nodig (stap 7 wijzigt geen app-code).
-- ============================================================
begin;

drop trigger if exists receipts_guard on public.receipts;
drop trigger if exists receipt_lines_guard on public.receipt_lines;
drop trigger if exists open_tabs_guard on public.open_tabs;
drop trigger if exists approvals_guard on public.approvals;
drop function if exists public.receipts_guard();
drop function if exists public.receipt_lines_guard();
drop function if exists public.open_tabs_guard();
drop function if exists public.approvals_guard();

drop policy if exists "open_tabs select" on public.open_tabs;
drop policy if exists "open_tabs insert" on public.open_tabs;
drop policy if exists "open_tabs update" on public.open_tabs;
drop policy if exists "open_tabs delete" on public.open_tabs;
drop policy if exists "receipts select" on public.receipts;
drop policy if exists "receipts insert" on public.receipts;
drop policy if exists "receipts update" on public.receipts;
drop policy if exists "receipts delete" on public.receipts;
drop policy if exists "receipt_lines select" on public.receipt_lines;
drop policy if exists "receipt_lines insert" on public.receipt_lines;
drop policy if exists "approvals select" on public.approvals;
drop policy if exists "approvals insert" on public.approvals;
drop policy if exists "approvals update" on public.approvals;

drop policy if exists "tenant isolation open_tabs" on public.open_tabs;
create policy "tenant isolation open_tabs" on public.open_tabs
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

drop policy if exists "tenant isolation receipts" on public.receipts;
create policy "tenant isolation receipts" on public.receipts
  for all using (
    restaurant_id in (select restaurant_id from users where users.id = auth.uid())
  );

drop policy if exists "tenant isolation receipt_lines" on public.receipt_lines;
create policy "tenant isolation receipt_lines" on public.receipt_lines
  for all using (
    receipt_id in (
      select r.id from receipts r
      where r.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

drop policy if exists "tenant isolation approvals" on public.approvals;
create policy "tenant isolation approvals" on public.approvals
  for all using (
    company_id in (
      select c.id from companies c
      where c.restaurant_id in (select restaurant_id from users where users.id = auth.uid())
    )
  );

commit;
