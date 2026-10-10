-- 0027 platformacties (architecture 13.19): actie + logregel in EEN transactie. Na 0026. Rollback: rollbacks/0027_rollback.sql
begin;
-- bestaat een functie al, dan faalt "create function": niets gewijzigd
do $m$ begin if to_regclass('public.platform_log') is null or to_regclass('public.platform_admins') is null then
  raise exception '0027 vooraf: 0026 ontbreekt, niets gewijzigd'; end if; end $m$;

create function public.platform_restaurant_aanmaken(p_admin uuid, p_naam text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid; begin
  if not exists (select 1 from platform_admins where user_id = p_admin and is_active) then
    raise exception 'geen platformbeheerder' using errcode = '42501'; end if;
  insert into restaurants (name) values (p_naam) returning id into v_id;
  insert into platform_log (admin_user_id, action, restaurant_id) values (p_admin, 'restaurant_aangemaakt', v_id);
  return v_id;
end $$;

create function public.platform_restaurant_status(p_admin uuid, p_restaurant uuid, p_aan boolean) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from platform_admins where user_id = p_admin and is_active) then
    raise exception 'geen platformbeheerder' using errcode = '42501'; end if;
  update restaurants set is_active = p_aan, updated_at = now() where id = p_restaurant;
  if not found then raise exception 'restaurant niet gevonden' using errcode = 'P0002'; end if;
  insert into platform_log (admin_user_id, action, restaurant_id) values (p_admin, case when p_aan then 'restaurant_aan' else 'restaurant_uit' end, p_restaurant);
  return p_aan;
end $$;

create function public.platform_eigenaar_koppelen(p_admin uuid, p_restaurant uuid, p_user uuid, p_naam text, p_email text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from platform_admins where user_id = p_admin and is_active) then
    raise exception 'geen platformbeheerder' using errcode = '42501'; end if;
  if not exists (select 1 from restaurants where id = p_restaurant) then raise exception 'restaurant niet gevonden' using errcode = 'P0002'; end if;
  insert into users (id, restaurant_id, full_name, role) values (p_user, p_restaurant, p_naam, 'owner');
  insert into platform_log (admin_user_id, action, restaurant_id, details) values (p_admin, 'eigenaar_uitgenodigd', p_restaurant, jsonb_build_object('email', p_email, 'user_id', p_user));
end $$;

revoke all on function public.platform_restaurant_aanmaken(uuid,text), public.platform_restaurant_status(uuid,uuid,boolean),
  public.platform_eigenaar_koppelen(uuid,uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.platform_restaurant_aanmaken(uuid,text), public.platform_restaurant_status(uuid,uuid,boolean),
  public.platform_eigenaar_koppelen(uuid,uuid,uuid,text,text) to service_role;
commit;
