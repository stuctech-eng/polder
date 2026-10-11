-- Rollback 0029 module-beheer. Eerst de app terug en 0030 terugdraaien. Weigert als het logboek al module-regels heeft (geen stil verlies).
begin;
do $m$ begin
if to_regprocedure('public.platform_module_zetten(uuid,uuid,text,boolean)') is null then
  raise exception '0029-rollback vooraf: 0029 niet aanwezig, niets gewijzigd';
elsif to_regprocedure('public.module_wacht()') is not null then
  raise exception '0029-rollback vooraf: eerst 0030 terugdraaien, niets gewijzigd';
elsif exists (select 1 from public.platform_log where action in ('module_aan', 'module_uit')) then
  raise exception '0029-rollback vooraf: logboek bevat al module-regels, niets gewijzigd'; end if; end $m$;
drop function public.platform_module_zetten(uuid,uuid,text,boolean);
alter table public.platform_log drop constraint platform_log_action_check, add constraint platform_log_action_check
  check (action in ('restaurant_aangemaakt','restaurant_aan','restaurant_uit','eigenaar_uitgenodigd'));
commit;
