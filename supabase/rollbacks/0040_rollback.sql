-- Rollback 0040 (wachten op PIN-instelling en goedkeuringsregel). NOODMAATREGEL.
-- Verwijdert precies de objecten van 0040, niets anders. Alleen als 0041 er (al) niet is.
begin;
do $m$ begin
if not (exists (select 1 from pg_trigger where tgname = 'approval_settings_pin_wacht') and exists (select 1 from pg_trigger where tgname = 'approvals_pin_wacht') and to_regprocedure('public.approval_settings_pin_wacht()') is not null and to_regprocedure('public.approvals_pin_wacht()') is not null) or (to_regprocedure('public.bon_indienen(uuid,text)') is not null)
then raise exception '0040-rollback vooraf: 0040 niet (precies) aanwezig of 0041 nog aanwezig, niets gewijzigd'; end if; end $m$;
drop trigger approval_settings_pin_wacht on public.approval_settings;
drop trigger approvals_pin_wacht on public.approvals;
drop function public.approval_settings_pin_wacht();
drop function public.approvals_pin_wacht();
do $m$ begin
if exists (select 1 from pg_trigger where tgname = 'approval_settings_pin_wacht') or exists (select 1 from pg_trigger where tgname = 'approvals_pin_wacht') or to_regprocedure('public.approval_settings_pin_wacht()') is not null or to_regprocedure('public.approvals_pin_wacht()') is not null then raise exception '0040-rollback achteraf: controle mislukt'; end if; end $m$;
commit;
