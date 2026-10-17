-- 0046 handtekening (14c, 4/6): wacht voor handtekeningbonnen. Na 0045. Rollback: rollbacks/0046_rollback.sql
-- Voor iedereen; weigert alleen. Draait als de aanroeper: mk = rol postgres EN markering van DEZE bon (alleen bon_ondertekenen).
-- Bon: handtekeningbon alleen met mk goed; mk alleen bij zo'n bon. Regel: handtekening alleen met mk, en met mk alleen dat.
begin;
do $m$ begin
if position('polder.ondertekening' in pg_get_functiondef('public.approvals_guard()'::regprocedure)) = 0
  or to_regprocedure('public.teken_wacht()') is not null then raise exception '0046 vooraf: stand wijkt af, niets gewijzigd'; end if; end $m$;

create function public.teken_wacht() returns trigger language plpgsql set search_path = public, pg_temp as $f$
declare mk boolean; eis boolean;
begin
  if tg_table_name = 'approvals' then
    mk := current_user = 'postgres' and coalesce(current_setting('polder.ondertekening', true), '') = new.receipt_id::text;
    eis := old.status = 'pending' and new.status = 'approved' and new.method = 'signature';
    if (not mk and (eis or new.signature_data is distinct from old.signature_data)) or (mk and not (eis and new.signature_data is not null)) then
      raise exception 'Een handtekening kan alleen via de klant worden gezet' using errcode = '42501'; end if;
    return new;
  end if;
  if not (old.status = 'pending_approval' and new.status in ('approved', 'locked')) then return new; end if;
  mk := current_user = 'postgres' and coalesce(current_setting('polder.ondertekening', true), '') = new.id::text;
  select case when count(*) > 0 then bool_or(method = 'signature') end into eis from approvals where receipt_id = new.id and status = 'pending';
  eis := coalesce(eis, exists (select 1 from open_tabs t join approval_settings s on s.company_id = t.company_id
                               where t.id = new.open_tab_id and s.method = 'signature'));
  if eis <> mk then raise exception 'Deze bon vraagt een handtekening van de klant' using errcode = '42501'; end if;
  return new;
end $f$;

revoke all on function public.teken_wacht() from public, anon, authenticated, service_role;
create trigger receipts_teken_wacht before update on public.receipts for each row execute function public.teken_wacht();
create trigger approvals_teken_wacht before update on public.approvals for each row execute function public.teken_wacht();

do $m$ begin
if (select count(*) from pg_proc where oid = to_regprocedure('public.teken_wacht()') and not prosecdef and pg_get_userbyid(proowner) = 'postgres'
    and proconfig = '{"search_path=public, pg_temp"}' and proacl::text = '{postgres=X/postgres}') <> 1
  or (select count(*) from pg_trigger where tgname like '%teken\_wacht' and tgenabled = 'O' and tgfoid = 'public.teken_wacht()'::regprocedure) <> 2
then raise exception '0046 achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
