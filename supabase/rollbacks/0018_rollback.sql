-- Rollback van migratie 0018 (stap 4, logboeken append-only). Brengt de stand van vóór 0018 terug.
-- Er is geen app-wijziging, dus geen gelijktijdige app-rollback nodig.
begin;

drop trigger if exists logs_append_only on public.activity_log;
drop trigger if exists logs_no_truncate on public.activity_log;
drop trigger if exists logs_append_only on public.audit_log;
drop trigger if exists logs_no_truncate on public.audit_log;
drop trigger if exists logs_append_only on public.domain_events;
drop trigger if exists logs_no_truncate on public.domain_events;
drop function if exists public.logs_append_only();
drop function if exists public.logs_no_truncate();

grant update, delete on public.activity_log, public.audit_log, public.domain_events to authenticated;

drop policy if exists "activity_log read own restaurant" on public.activity_log;
drop policy if exists "activity_log insert own" on public.activity_log;
drop policy if exists "tenant isolation activity_log" on public.activity_log;
create policy "tenant isolation activity_log" on public.activity_log
  for all using (restaurant_id in (select restaurant_id from users where users.id = auth.uid()));

drop policy if exists "audit_log read own restaurant" on public.audit_log;
drop policy if exists "audit_log insert own" on public.audit_log;
drop policy if exists "tenant isolation audit_log" on public.audit_log;
create policy "tenant isolation audit_log" on public.audit_log
  for all using (restaurant_id in (select restaurant_id from users where users.id = auth.uid()));

drop policy if exists "domain_events read own restaurant" on public.domain_events;
drop policy if exists "domain_events insert own" on public.domain_events;
drop policy if exists "tenant isolation domain_events" on public.domain_events;
create policy "tenant isolation domain_events" on public.domain_events
  for all using (restaurant_id in (select restaurant_id from users where users.id = auth.uid()));

commit;
