-- 0039 PIN-pogingen: reserveren (stap 14a, deel 3 van 5). Na 0038. Rollback: rollbacks/0039_rollback.sql
-- Telt vooraf (een poging is fout tot het tegendeel blijkt); hooguit 5 lopend/fout per glijdend venster van 15 minuten per
-- bedrijf en generatie; de 5e zet een blokkade van 15 minuten. Tijd en telling pas na het bedrijfsslot (clock_timestamp).
begin;
do $m$ begin
if to_regprocedure('public.pin_eis(uuid)') is null or to_regprocedure('public.pin_poging_start(uuid,uuid)') is not null
then raise exception '0039 vooraf: 0038 ontbreekt of functie bestaat al, niets gewijzigd'; end if; end $m$;

create function public.pin_poging_start(p_company uuid, p_bon uuid) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $f$
declare s pin_pogingen; t timestamptz; n int; v uuid; tab uuid; st text;
begin
  select open_tab_id, status into tab, st from receipts where id = p_bon;
  perform 1 from open_tabs where id = tab for share;
  if st is distinct from 'pending_approval' or pin_eis(p_bon) is distinct from p_company then
    return jsonb_build_object('toegestaan', false, 'reden', 'ongeldig'); end if;
  insert into pin_pogingen (company_id) values (p_company) on conflict do nothing;
  select * into s from pin_pogingen where company_id = p_company for update;
  t := clock_timestamp();
  if s.geblokkeerd_tot > t then
    return jsonb_build_object('toegestaan', false, 'reden', 'geblokkeerd', 'geblokkeerd_tot', s.geblokkeerd_tot); end if;
  delete from pin_reserveringen where company_id = p_company and gemaakt_op < t - interval '1 day';
  select count(*) into n from pin_reserveringen where company_id = p_company and generatie = s.generatie
    and gemaakt_op > t - interval '15 minutes' and status in ('lopend', 'fout');
  if n >= 5 then return jsonb_build_object('toegestaan', false, 'reden', 'geblokkeerd'); end if;
  insert into pin_reserveringen (company_id, receipt_id, generatie, gemaakt_op) values (p_company, p_bon, s.generatie, t) returning id into v;
  if n = 4 then update pin_pogingen set geblokkeerd_tot = t + interval '15 minutes' where company_id = p_company; end if;
  return jsonb_build_object('toegestaan', true, 'id', v, 'resterend', 4 - n, 'blokkade_gezet', n = 4,
    'geblokkeerd_tot', case when n = 4 then t + interval '15 minutes' end);
end $f$;

revoke all on function public.pin_poging_start(uuid, uuid) from public, anon, authenticated;
grant execute on function public.pin_poging_start(uuid, uuid) to service_role;

do $m$ begin
if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('pin_poging_start') and prosecdef
    and pg_get_userbyid(proowner) = 'postgres' and proconfig = '{"search_path=public, pg_temp"}'
    and (select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text) from aclexplode(proacl) x) = 'postgres,service_role') <> 1
then raise exception '0039 achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
