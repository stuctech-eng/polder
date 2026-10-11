-- 0028 modules per restaurant (architecture 13.21). Na 0027. Rollback: rollbacks/0028_rollback.sql
begin;
do $m$ begin
if md5(btrim(regexp_replace((select prosrc from pg_proc where oid=to_regprocedure('public.platform_restaurant_status(uuid,uuid,boolean)')),'\s+',' ','g')))
  is distinct from 'cb78b3d569496a1f675ed9fec4738633'
or to_regclass('public.features') is not null or to_regclass('public.restaurant_features') is not null
or to_regprocedure('public.feature_aan(uuid,text)') is not null then
  raise exception '0028 vooraf: uitgangsstand wijkt af, niets gewijzigd'; end if; end $m$;

create table public.features (key text primary key, default_enabled boolean not null, description text not null);
insert into public.features values ('daily_closing', true, 'Dagafsluiting'),
  ('payment_registration', true, 'Betalingen registreren'), ('approval', true, 'Goedkeuring');
create table public.restaurant_features (restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  feature text not null references public.features(key), enabled boolean not null,
  updated_at timestamptz not null default now(), primary key (restaurant_id, feature));
alter table public.features enable row level security;
alter table public.restaurant_features enable row level security;
revoke all on public.features, public.restaurant_features from public, anon, authenticated, service_role;
grant select on public.features, public.restaurant_features to service_role;

create function public.feature_aan(p_restaurant uuid, p_key text) returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select coalesce((select coalesce(rf.enabled, f.default_enabled) from public.features f join public.restaurants r on r.id = p_restaurant
    left join public.restaurant_features rf on rf.restaurant_id = r.id and rf.feature = f.key where f.key = p_key), false)
$$;
create function public.my_feature(p_key text) returns boolean language sql stable security definer
set search_path = public, pg_temp as $$ select public.feature_aan(public.my_restaurant_id(), p_key) $$;

revoke all on function public.feature_aan(uuid,text), public.my_feature(text) from public, anon, authenticated, service_role;
grant execute on function public.feature_aan(uuid,text) to service_role;
grant execute on function public.my_feature(text) to authenticated;
do $m$ begin
if (select count(*) from public.features where default_enabled) <> 3 or exists (select 1 from public.restaurant_features)
or exists (select 1 from public.restaurants r where not public.feature_aan(r.id, 'approval') or public.feature_aan(r.id, 'x'))
or has_function_privilege('authenticated', 'public.feature_aan(uuid,text)', 'EXECUTE')
or has_function_privilege('anon', 'public.my_feature(text)', 'EXECUTE')
or has_table_privilege('authenticated', 'public.restaurant_features', 'SELECT,INSERT,UPDATE,DELETE') then
  raise exception '0028 achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
