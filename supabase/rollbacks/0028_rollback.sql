-- Rollback 0028 modules: register, instellingen en functies weg. Eerst de app terug en 0030 en 0029 terugdraaien.
-- Weigert als een restaurant een afwijkende instelling heeft (geen stille heractivering).
begin;
do $m$ begin
if to_regprocedure('public.feature_aan(uuid,text)') is null or to_regclass('public.restaurant_features') is null then
  raise exception '0028-rollback vooraf: 0028 niet (volledig) aanwezig, niets gewijzigd';
elsif to_regprocedure('public.platform_module_zetten(uuid,uuid,text,boolean)') is not null or to_regprocedure('public.module_wacht()') is not null then
  raise exception '0028-rollback vooraf: eerst 0030 en 0029 terugdraaien, niets gewijzigd';
elsif exists (select 1 from public.restaurant_features) then
  raise exception '0028-rollback vooraf: er zijn module-instellingen per restaurant, niets gewijzigd'; end if; end $m$;
drop function public.my_feature(text);
drop function public.feature_aan(uuid,text);
drop table public.restaurant_features;
drop table public.features;
commit;
