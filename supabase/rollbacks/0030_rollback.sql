-- Rollback 0030 databasewacht modules. Verwijdert alleen de 6 module_wacht-triggers en de functie; bestaande guards blijven onaangeroerd.
begin;
do $m$ begin
if to_regprocedure('public.module_wacht()') is null or (select count(*) from pg_trigger where tgname = 'module_wacht') <> 6 then
  raise exception '0030-rollback vooraf: 0030 niet (volledig) aanwezig, niets gewijzigd'; end if; end $m$;
drop trigger module_wacht on public.payments;
drop trigger module_wacht on public.invoices;
drop trigger module_wacht on public.daily_closings;
drop trigger module_wacht on public.approval_settings;
drop trigger module_wacht on public.approvals;
drop trigger module_wacht on public.receipts;
drop function public.module_wacht();
commit;
