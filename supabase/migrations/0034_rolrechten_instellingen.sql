-- 0034 rolrechten instellingen en ongebruikte tabellen (hardening stap 11, architecture 13.23). Na 0033. Rollback: rollbacks/0034_rollback.sql
-- instellingen: lezen iedereen, schrijven MANAGE_SETTINGS, nooit wissen. Ongebruikt (contacts, integration_plugins, email_settings,
-- notifications): geen policy meer = dicht voor restaurantrollen. Daarna bestaat er geen ALL-policy meer in public.
-- email_settings (migratie 0002) bestaat in productie niet: wordt alleen meegenomen als de tabel bestaat.
begin;
do $m$
declare t text; r text := 'restaurant_id = public.my_restaurant_id()'; k text;
  l text[] := array['configurations','workflow_rules','approval_settings','contacts','integration_plugins','notifications'];
begin
if to_regclass('public.email_settings') is not null then l := l || 'email_settings'::text; end if;
if not exists (select 1 from pg_policies where schemaname = 'public' and policyname = 'daily_closings insert')
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> cardinality(l)
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l) and cmd = 'ALL'
      and policyname = 'tenant isolation ' || tablename) <> cardinality(l)
then raise exception '0034 vooraf: uitgangsstand wijkt af, niets gewijzigd'; end if;

foreach t in array l loop execute format('drop policy %I on public.%I', 'tenant isolation ' || t, t); end loop;

foreach t in array l[1:3] loop
  k := case when t = 'approval_settings'
       then format('exists (select 1 from public.companies c where c.id = approval_settings.company_id and c.%s)', r) else r end;
  execute format('create policy %I on public.%I for select to authenticated using (%s)', t || ' select', t, k);
  k := k || ' and public.has_perm(''MANAGE_SETTINGS'')';
  execute format('create policy %I on public.%I for insert to authenticated with check (%s)', t || ' insert', t, k);
  execute format('create policy %1$I on public.%2$I for update to authenticated using (%3$s) with check (%3$s)', t || ' update', t, k);
end loop;

if (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 9
  or exists (select 1 from pg_policies where schemaname = 'public' and (cmd = 'ALL' or (tablename = any(l) and roles <> '{authenticated}')))
  or exists (select 1 from pg_class where relnamespace = 'public'::regnamespace and relname = any(l) and not relrowsecurity)
then raise exception '0034 achteraf: controle mislukt, niets gewijzigd'; end if;
end $m$;
commit;
