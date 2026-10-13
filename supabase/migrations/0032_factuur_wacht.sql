-- 0032 factuurwacht (stap 10, architecture 13.22), voor iedereen; definer: ziet de echte factuur. Na 0031. Rollback: rollbacks/0032_rollback.sql
-- D6: draft->sent|paid, sent->paid|overdue, overdue->paid. Na draft alleen de status; paid is eindstand.
begin;
do $m$ begin if not exists (select 1 from pg_policies where policyname = 'invoices update')
  or to_regprocedure('public.invoices_guard()') is not null then raise exception '0032 vooraf: stand wijkt af'; end if; end $m$;

create function public.invoices_guard() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() > 1 and not exists (select 1 from restaurants where id = old.restaurant_id) then return old; end if;
    if old.status <> 'draft' then raise exception 'Alleen een draft-factuur kan weg'; end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then raise exception 'Nieuwe factuur moet draft zijn'; end if;
    return new;
  end if;
  if new.status <> old.status and (old.status, new.status) not in
     (('draft','sent'), ('draft','paid'), ('sent','paid'), ('sent','overdue'), ('overdue','paid')) then
    raise exception 'Ongeldige factuurstatus: % -> %', old.status, new.status;
  end if;
  if old.status <> 'draft' and to_jsonb(new) - 'status' <> to_jsonb(old) - 'status' then
    raise exception 'Na draft verandert alleen de factuurstatus';
  end if;
  return new;
end $$;

create function public.invoice_child_guard() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare j jsonb := to_jsonb(coalesce(new, old)); s text;
begin
  select status into s from invoices where id = (j->>'invoice_id')::uuid;
  if not found and tg_op = 'DELETE' and pg_trigger_depth() > 1 then return old; end if;
  if tg_table_name = 'invoice_lines' and (s is distinct from 'draft' or old.invoice_id <> new.invoice_id) then
    raise exception 'Factuurregel: factuur niet draft of verplaatst';
  end if;
  if tg_table_name = 'payments' and (s is null or s = 'paid' or not (new.amount > 0)) then
    raise exception 'Betaling geweigerd (factuur betaald of bedrag <= 0)';
  end if;
  return coalesce(new, old);
end $$;

revoke all on function invoices_guard(), invoice_child_guard() from public, anon, authenticated, service_role;
create trigger invoices_guard before insert or update or delete on public.invoices for each row execute function public.invoices_guard();
create trigger invoice_child_guard before insert or update or delete on public.invoice_lines for each row execute function public.invoice_child_guard();
create trigger invoice_child_guard before insert on public.payments for each row execute function public.invoice_child_guard();

do $m$ begin if (select count(*) from pg_trigger where tgname in ('invoices_guard','invoice_child_guard')) <> 3 then
  raise exception '0032 achteraf: mislukt'; end if; end $m$;
commit;
