-- 0030 databasewacht modules (architecture 13.21): module uit = schrijfactie geweigerd, voor iedereen. Na 0029. Rollback: rollbacks/0030_rollback.sql
begin;
do $m$ begin if to_regprocedure('public.feature_aan(uuid,text)') is null or to_regprocedure('public.module_wacht()') is not null then
  raise exception '0030 vooraf: uitgangsstand wijkt af, niets gewijzigd'; end if; end $m$;

create function public.module_wacht() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare j jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end; v_rest uuid; v_key text; v_ouder boolean;
begin
  if tg_table_name = 'payments' then
    v_key := 'payment_registration'; select restaurant_id into v_rest from invoices where id = (j->>'invoice_id')::uuid; v_ouder := found;
  elsif tg_table_name = 'invoices' then
    if not (new.status = 'paid' and old.status is distinct from 'paid') then return new; end if;
    v_key := 'payment_registration'; v_rest := new.restaurant_id;
  elsif tg_table_name = 'daily_closings' then
    v_key := 'daily_closing'; v_rest := (j->>'restaurant_id')::uuid; v_ouder := exists (select 1 from restaurants where id = v_rest);
  elsif tg_table_name = 'approval_settings' then
    v_key := 'approval'; select restaurant_id into v_rest from companies where id = (j->>'company_id')::uuid; v_ouder := found;
  elsif tg_table_name = 'approvals' then
    v_key := 'approval'; select restaurant_id into v_rest from receipts where id = new.receipt_id;
  elsif tg_table_name = 'receipts' then
    if not ((old.status = 'pending_approval' and new.status is distinct from old.status)
            or (old.status = 'approved' and new.status = 'locked')) then return new; end if;
    v_key := 'approval'; v_rest := new.restaurant_id;
  end if;
  -- cascade: de ouderrij (factuur, bedrijf, restaurant) is al weg
  if tg_op = 'DELETE' and pg_trigger_depth() > 1 and not v_ouder then return old; end if;
  if v_key is null or not feature_aan(v_rest, v_key) then
    raise exception 'Module % staat uit voor dit restaurant', coalesce(v_key, '?') using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
revoke all on function public.module_wacht() from public, anon, authenticated, service_role;

do $m$ declare t text[]; begin foreach t slice 1 in array array[['payments','insert or update or delete'],['invoices','update of status'],
  ['daily_closings','insert or update or delete'],['approval_settings','insert or update or delete'],['approvals','update'],['receipts','update of status']]
loop execute format('create trigger module_wacht before %s on public.%I for each row execute function public.module_wacht()', t[2], t[1]); end loop; end $m$;

do $m$ begin if (select count(*) from pg_trigger where tgname = 'module_wacht') <> 6 then
  raise exception '0030 achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
