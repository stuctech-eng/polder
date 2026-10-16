-- Rollback 0037 (tabellen). NOODMAATREGEL.
-- Tellerstanden en reserveringen gaan verloren (geen andere gegevens).
-- Verwijdert precies de objecten van 0037, niets anders. Alleen als 0038 er (al) niet is.
begin;
do $m$ begin
if not (to_regclass('public.pin_pogingen') is not null and to_regclass('public.pin_reserveringen') is not null) or (to_regprocedure('public.pin_eis(uuid)') is not null or to_regprocedure('public.pin_poging_afronden(uuid,boolean)') is not null)
then raise exception '0037-rollback vooraf: 0037 niet (precies) aanwezig of 0038 nog aanwezig, niets gewijzigd'; end if; end $m$;
drop table public.pin_reserveringen;
drop table public.pin_pogingen;
do $m$ begin
if to_regclass('public.pin_pogingen') is not null or to_regclass('public.pin_reserveringen') is not null then raise exception '0037-rollback achteraf: controle mislukt'; end if; end $m$;
commit;
