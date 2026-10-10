-- POLDER — platformbeheerder toevoegen (na migratie 0026). Wijzigt productie: alleen met GO.
-- Alleen een bestaand account ZONDER restaurantprofiel (B1: apart account); anders breekt het af en wijzigt niets.
begin;
do $m$ declare v_id uuid; begin
  select id into v_id from auth.users where lower(email) = 'stuctech@gmail.com';
  if v_id is null then raise exception 'beheerder: account bestaat niet, niets gewijzigd'; end if;
  if exists (select 1 from public.users where id = v_id) then
    raise exception 'beheerder: account heeft een restaurantprofiel, niets gewijzigd'; end if;
  if exists (select 1 from public.platform_admins where user_id = v_id) then
    raise exception 'beheerder: staat al in de lijst, niets gewijzigd'; end if;
  insert into public.platform_admins (user_id) values (v_id);
end $m$;
select a.email, p.is_active, p.created_at from public.platform_admins p join auth.users a on a.id = p.user_id;
commit;
