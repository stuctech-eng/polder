-- Rollback 0034 rolrechten instellingen. NOODMAATREGEL: zet de oude policies terug ("alleen eigen restaurant"), en daarmee ook het
-- oude lek (elke rol mag instellingen wijzigen en wissen; ongebruikte tabellen weer open). Alleen tijdelijk. 0033 blijft staan.
begin;
do $m$
declare t text; l text[] := array['configurations','workflow_rules','approval_settings','contacts','integration_plugins','email_settings','notifications'];
begin
if (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 9
  or exists (select 1 from pg_policies where schemaname = 'public' and tablename = any(l) and policyname like 'tenant isolation %') then
  raise exception '0034-rollback vooraf: 0034 niet (volledig) aanwezig, niets gewijzigd'; end if;
foreach t in array l[1:3] loop
  execute (select string_agg(format('drop policy %I on public.%I;', policyname, t), ' ') from pg_policies where schemaname = 'public' and tablename = t);
end loop;
foreach t in array array['configurations','workflow_rules','integration_plugins','notifications'] loop
  execute format('create policy %I on public.%I using (restaurant_id = public.my_restaurant_id())', 'tenant isolation ' || t, t);
end loop;
foreach t in array array['approval_settings','contacts'] loop
  execute format('create policy %I on public.%I using (exists (select 1 from public.companies c where c.id = %I.company_id and c.restaurant_id = public.my_restaurant_id()))',
    'tenant isolation ' || t, t, t);
end loop;
create policy "tenant isolation email_settings" on public.email_settings
  using (restaurant_id in (select users.restaurant_id from public.users where users.id = auth.uid()));
if (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l) and cmd = 'ALL') <> 7
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 7 then
  raise exception '0034-rollback achteraf: controle mislukt'; end if;
end $m$;
commit;
