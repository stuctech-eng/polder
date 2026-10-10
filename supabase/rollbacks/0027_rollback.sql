-- Rollback 0027 platformacties. Eerst de app terugzetten (de beheerschermen gebruiken deze functies). Tabellen en logboek blijven.
begin;
do $m$ begin
if to_regprocedure('public.platform_restaurant_aanmaken(uuid,text)') is null
or to_regprocedure('public.platform_restaurant_status(uuid,uuid,boolean)') is null
or to_regprocedure('public.platform_eigenaar_koppelen(uuid,uuid,uuid,text,text)') is null then
  raise exception '0027-rollback vooraf: 0027 niet (volledig) aanwezig, niets gewijzigd';
end if; end $m$;
drop function public.platform_restaurant_aanmaken(uuid,text);
drop function public.platform_restaurant_status(uuid,uuid,boolean);
drop function public.platform_eigenaar_koppelen(uuid,uuid,uuid,text,text);
commit;
