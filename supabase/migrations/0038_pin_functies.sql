-- 0038 PIN: pin_eis en afronden (14a, 2/5). Na 0037. Rollback: rollbacks/0038_rollback.sql
-- Alleen service_role (route na requireRole).
begin;
do $m$ begin
if to_regclass('public.pin_reserveringen') is null
  or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname in ('pin_eis','pin_poging_afronden'))
then raise exception '0038 vooraf: stand wijkt af, niets gewijzigd'; end if; end $m$;

-- wachtende PIN-regel -> dat bedrijf; andere wachtende regel -> geen; anders huidig bedrijf
create function public.pin_eis(p_bon uuid) returns uuid language plpgsql volatile security definer
set search_path = public, pg_temp as $f$
declare n int; c uuid; r boolean;
begin
  select count(distinct company_id) filter (where method = 'pin'), min(company_id::text) filter (where method = 'pin'), count(*) > 0
    into n, c, r from approvals where receipt_id = p_bon and status = 'pending';
  if n > 1 then raise exception 'PIN-eis: meerdere bedrijven' using errcode = 'check_violation'; end if;
  if r then return c; end if;
  select t.company_id into c from receipts b join open_tabs t on t.id = b.open_tab_id
    join approval_settings s on s.company_id = t.company_id where b.id = p_bon and s.method = 'pin';
  return c;
end $f$;

-- ok|verlopen|al_afgerond|onbekend; alleen vanuit lopend
create function public.pin_poging_afronden(p_id uuid, p_juist boolean) returns text language plpgsql security definer
set search_path = public, pg_temp as $f$
declare r pin_reserveringen; g bigint;
begin
  if p_juist is null then raise exception 'juist is verplicht'; end if;
  select * into r from pin_reserveringen where id = p_id;
  if not found then return 'onbekend'; end if;
  select generatie into g from pin_pogingen where company_id = r.company_id for update;
  select * into r from pin_reserveringen where id = p_id for update;
  if not found then return 'onbekend'; end if;
  if r.status <> 'lopend' then return 'al_afgerond'; end if;
  if r.generatie <> g then
    update pin_reserveringen set status = 'verlopen', afgerond_op = clock_timestamp() where id = p_id; return 'verlopen'; end if;
  update pin_reserveringen set status = case when p_juist then 'juist' else 'fout' end, afgerond_op = clock_timestamp() where id = p_id;
  return 'ok';
end $f$;

revoke all on function public.pin_eis(uuid), public.pin_poging_afronden(uuid, boolean) from public, anon, authenticated;
grant execute on function public.pin_eis(uuid), public.pin_poging_afronden(uuid, boolean) to service_role;

do $m$ begin
if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('pin_eis','pin_poging_afronden') and prosecdef
    and pg_get_userbyid(proowner) = 'postgres' and proconfig = '{"search_path=public, pg_temp"}'
    and (select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text) from aclexplode(proacl) x) = 'postgres,service_role') <> 2
then raise exception '0038 achteraf: mislukt, niets gewijzigd'; end if; end $m$;
commit;
