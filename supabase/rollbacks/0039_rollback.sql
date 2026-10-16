-- Rollback 0039 (reserveren). NOODMAATREGEL.
-- Verwijdert precies de objecten van 0039, niets anders. Alleen als 0040 er (al) niet is.
begin;
do $m$ begin
if not (to_regprocedure('public.pin_poging_start(uuid,uuid)') is not null) or (to_regprocedure('public.approval_settings_pin_wacht()') is not null or to_regprocedure('public.approvals_pin_wacht()') is not null)
then raise exception '0039-rollback vooraf: 0039 niet (precies) aanwezig of 0040 nog aanwezig, niets gewijzigd'; end if; end $m$;
drop function public.pin_poging_start(uuid, uuid);
do $m$ begin
if to_regprocedure('public.pin_poging_start(uuid,uuid)') is not null then raise exception '0039-rollback achteraf: controle mislukt'; end if; end $m$;
commit;
