-- Rollback 0038 (pin_eis en afronden). NOODMAATREGEL.
-- Verwijdert precies de objecten van 0038, niets anders. Alleen als 0039 er (al) niet is.
begin;
do $m$ begin
if not (to_regprocedure('public.pin_eis(uuid)') is not null and to_regprocedure('public.pin_poging_afronden(uuid,boolean)') is not null) or (to_regprocedure('public.pin_poging_start(uuid,uuid)') is not null)
then raise exception '0038-rollback vooraf: 0038 niet (precies) aanwezig of 0039 nog aanwezig, niets gewijzigd'; end if; end $m$;
drop function public.pin_eis(uuid);
drop function public.pin_poging_afronden(uuid, boolean);
do $m$ begin
if to_regprocedure('public.pin_eis(uuid)') is not null or to_regprocedure('public.pin_poging_afronden(uuid,boolean)') is not null then raise exception '0038-rollback achteraf: controle mislukt'; end if; end $m$;
commit;
