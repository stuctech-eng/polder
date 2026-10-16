-- Rollback 0041 (bon indienen in een keer). NOODMAATREGEL.
-- Daarna moet de app weer de oude manier van indienen gebruiken (eerst de app terugzetten, dan deze rollback).
-- Verwijdert precies de objecten van 0041, niets anders. Alleen als 0042 er (al) niet is.
begin;
do $m$ begin
if to_regprocedure('public.bon_indienen(uuid,text)') is null or to_regprocedure('public.receipts_pin_wacht()') is not null
then raise exception '0041-rollback vooraf: 0041 niet aanwezig of 0042 nog aanwezig, niets gewijzigd'; end if; end $m$;
drop function public.bon_indienen(uuid, text);
do $m$ begin
if to_regprocedure('public.bon_indienen(uuid,text)') is not null then raise exception '0041-rollback achteraf: controle mislukt'; end if; end $m$;
commit;
