-- 0040 PIN: wachten instelling en regel (14a, 4/5). Na 0039. Rollback: rollbacks/0040_rollback.sql
-- Nieuwe PIN: generatie + 1. Nieuwe regel = methode bedrijf. PIN-regel pas na de bon. Oude app werkt.
begin;
do $m$ begin
if to_regprocedure('public.pin_poging_start(uuid,uuid)') is null or to_regprocedure('public.approval_settings_pin_wacht()') is not null
  or to_regprocedure('public.approvals_pin_wacht()') is not null
then raise exception '0040 vooraf: stand wijkt af, niets gewijzigd'; end if; end $m$;

create function public.approval_settings_pin_wacht() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
begin
  if new.pin_hash is null or (tg_op = 'UPDATE' and new.pin_hash is not distinct from old.pin_hash) then return new; end if;
  insert into pin_pogingen (company_id) values (new.company_id) on conflict do nothing;
  update pin_pogingen set generatie = generatie + 1, geblokkeerd_tot = null where company_id = new.company_id;
  return new;
end $f$;

create function public.approvals_pin_wacht() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
begin
  if tg_op = 'INSERT' then
    if new.method is distinct from (select method from approval_settings where company_id = new.company_id) then
      raise exception 'Methode wijkt af van de bedrijfsinstelling' using errcode = 'check_violation'; end if;
  elsif old.status = 'pending' and new.status = 'approved' and new.method = 'pin'
     and not exists (select 1 from receipts where id = new.receipt_id and status in ('approved', 'locked')) then
    raise exception 'Een PIN-goedkeuring kan pas na goedkeuring van de bon' using errcode = 'insufficient_privilege'; end if;
  return new;
end $f$;

revoke all on function public.approval_settings_pin_wacht(), public.approvals_pin_wacht() from public, anon, authenticated, service_role;
create trigger approval_settings_pin_wacht before insert or update of pin_hash on public.approval_settings
  for each row execute function public.approval_settings_pin_wacht();
create trigger approvals_pin_wacht before insert or update on public.approvals for each row execute function public.approvals_pin_wacht();

do $m$ begin
if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('approval_settings_pin_wacht','approvals_pin_wacht') and prosecdef
    and pg_get_userbyid(proowner) = 'postgres' and proconfig = '{"search_path=public, pg_temp"}'
    and (select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text) from aclexplode(proacl) x) = 'postgres') <> 2
then raise exception '0040 achteraf: mislukt, niets gewijzigd'; end if; end $m$;
do $m$ begin
if (select count(*) from pg_trigger where tgname in ('approval_settings_pin_wacht','approvals_pin_wacht') and tgenabled = 'O' and tgfoid = to_regprocedure('public.' || tgname || '()')) <> 2
then raise exception '0040 achteraf: wachten ontbreken, niets gewijzigd'; end if; end $m$;
commit;
