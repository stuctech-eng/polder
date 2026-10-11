-- 0029 module aan/uit door de platformbeheerder: wijziging + logregel in EEN transactie (architecture 13.21). Na 0028.
-- Rollback: rollbacks/0029_rollback.sql
begin;
do $m$ begin
if to_regprocedure('public.feature_aan(uuid,text)') is null or to_regprocedure('public.platform_module_zetten(uuid,uuid,text,boolean)') is not null
or (select pg_get_constraintdef(oid) from pg_constraint where conname = 'platform_log_action_check' and conrelid = 'public.platform_log'::regclass)
  <> 'CHECK ((action = ANY (ARRAY[''restaurant_aangemaakt''::text, ''restaurant_aan''::text, ''restaurant_uit''::text, ''eigenaar_uitgenodigd''::text])))' then
  raise exception '0029 vooraf: uitgangsstand wijkt af, niets gewijzigd'; end if; end $m$;

alter table public.platform_log drop constraint platform_log_action_check, add constraint platform_log_action_check check (action in
  ('restaurant_aangemaakt','restaurant_aan','restaurant_uit','eigenaar_uitgenodigd','module_aan','module_uit'));

create function public.platform_module_zetten(p_admin uuid, p_restaurant uuid, p_key text, p_aan boolean) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from platform_admins where user_id = p_admin and is_active) then
    raise exception 'geen platformbeheerder' using errcode = '42501'; end if;
  if not exists (select 1 from restaurants where id = p_restaurant) then raise exception 'restaurant niet gevonden' using errcode = 'P0002'; end if;
  if not exists (select 1 from features where key = p_key) then raise exception 'onbekende module' using errcode = '22023'; end if;
  insert into restaurant_features values (p_restaurant, p_key, p_aan, now())
    on conflict (restaurant_id, feature) do update set enabled = excluded.enabled, updated_at = now();
  insert into platform_log (admin_user_id, action, restaurant_id, details)
    values (p_admin, case when p_aan then 'module_aan' else 'module_uit' end, p_restaurant, jsonb_build_object('module', p_key));
  return p_aan;
end $$;

revoke all on function public.platform_module_zetten(uuid,uuid,text,boolean) from public, anon, authenticated, service_role;
grant execute on function public.platform_module_zetten(uuid,uuid,text,boolean) to service_role;
commit;
