-- 0042 PIN-pogingen: wacht op de bon (stap 14a, deel 6 van 6). Na 0041 en NA de nieuwe app (fase B). Rollback: rollbacks/0042_rollback.sql
-- LET OP: pas uitvoeren als de NIEUWE app (fase B) live is: de oude app kan hierna een PIN-bon niet meer goedkeuren (geen reservering).
-- De wacht kan alleen weigeren; ze passen NEW niet aan. Geen uitzondering voor service_role.
begin;
do $m$ begin
if to_regprocedure('public.bon_indienen(uuid,text)') is null or to_regprocedure('public.approval_settings_pin_wacht()') is null
  or to_regprocedure('public.approvals_pin_wacht()') is null or exists (select 1 from pg_trigger where tgname = 'receipts_pin_wacht')
then raise exception '0042 vooraf: 0041 ontbreekt of wachten bestaan al, niets gewijzigd'; end if; end $m$;

-- bon pending_approval -> approved/locked: eist een juiste, onverbruikte reservering (< 2 min) van deze bon, dit bedrijf, deze generatie
create function public.receipts_pin_wacht() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
declare c uuid; g bigint; v uuid;
begin
  if not (old.status = 'pending_approval' and new.status in ('approved', 'locked')) then return new; end if;
  perform 1 from open_tabs where id = old.open_tab_id for share;
  c := pin_eis(new.id);
  if c is null then return new; end if;
  insert into pin_pogingen (company_id) values (c) on conflict do nothing;
  select generatie into g from pin_pogingen where company_id = c for update;
  select id into v from pin_reserveringen where receipt_id = new.id and company_id = c and generatie = g and status = 'juist'
    and verbruikt_op is null and afgerond_op > clock_timestamp() - interval '2 minutes' order by afgerond_op desc limit 1 for update;
  if v is null then raise exception 'PIN-goedkeuring ontbreekt of is verlopen' using errcode = 'insufficient_privilege'; end if;
  update pin_reserveringen set verbruikt_op = clock_timestamp() where id = v;
  return new;
end $f$;

revoke all on function public.receipts_pin_wacht() from public, anon, authenticated, service_role;
create trigger receipts_pin_wacht before update on public.receipts for each row execute function public.receipts_pin_wacht();

do $m$ begin
if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('receipts_pin_wacht') and prosecdef
    and pg_get_userbyid(proowner) = 'postgres' and proconfig = '{"search_path=public, pg_temp"}'
    and (select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text) from aclexplode(proacl) x) = 'postgres') <> 1
then raise exception '0042 achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
do $m$ begin
if (select count(*) from pg_trigger where tgname in ('receipts_pin_wacht') and tgenabled = 'O' and tgfoid = to_regprocedure('public.' || tgname || '()')) <> 1
then raise exception '0042 achteraf: wachten niet (goed) aanwezig, niets gewijzigd'; end if; end $m$;
commit;
