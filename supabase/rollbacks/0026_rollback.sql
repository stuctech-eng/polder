-- Rollback 0026 platformbeheer. Eerst de app terugzetten en 0027 terugdraaien (die functies gebruiken deze tabellen).
-- Let op: verwijdert ook de beheerderslijst en het platformlogboek.
begin;
do $m$ begin
if to_regclass('public.platform_admins') is null or to_regclass('public.platform_log') is null
or to_regprocedure('public.is_platform_admin()') is null then
  raise exception '0026-rollback vooraf: 0026 niet (volledig) aanwezig, niets gewijzigd';
elsif to_regprocedure('public.platform_restaurant_status(uuid,uuid,boolean)') is not null then
  raise exception '0026-rollback vooraf: eerst 0027 terugdraaien, niets gewijzigd';
end if; end $m$;
drop function public.is_platform_admin();
drop table public.platform_log;
drop table public.platform_admins;
do $m$ begin
if to_regclass('public.platform_admins') is not null or to_regclass('public.platform_log') is not null
or to_regprocedure('public.is_platform_admin()') is not null then
  raise exception '0026-rollback achteraf: controle mislukt, niets gewijzigd';
end if; end $m$;
commit;
