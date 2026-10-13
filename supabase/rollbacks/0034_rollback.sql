-- Rollback 0034 rolrechten instellingen. NOODMAATREGEL: zet de oude policies terug ("alleen eigen restaurant"), en daarmee ook het
-- oude lek (elke rol mag instellingen wijzigen en wissen; ongebruikte tabellen weer open). Alleen tijdelijk. 0033 blijft staan.
begin;
do $m$
declare t text; l text[] := array['configurations','workflow_rules','approval_settings','contacts','integration_plugins','notifications'];
begin
if to_regclass('public.email_settings') is not null then l := l || 'email_settings'::text; end if;  -- bestaat in productie niet
-- precies de 9 policies van 0034 (tabel, naam, bewerking, rol), en verder niets op deze tabellen; anders afbreken
if (select string_agg(x, '|' order by x) from (select tablename || ':' || policyname || ':' || cmd || ':' || array_to_string(roles, ',') x
    from pg_policies where schemaname = 'public' and tablename = any(l)) p) is distinct from
   (select string_agg(x, '|' order by x) from (select tb || ':' || tb || ' ' || op || ':' || upper(op) || ':authenticated' x
    from unnest(l[1:3]) tb cross join unnest(array['select','insert','update']) op) e) then
  raise exception '0034-rollback vooraf: policies wijken af van 0034, niets gewijzigd'; end if;
foreach t in array l[1:3] loop
  execute format('drop policy %I on public.%I; drop policy %I on public.%I; drop policy %I on public.%I;',
    t || ' select', t, t || ' insert', t, t || ' update', t);
end loop;
foreach t in array array['configurations','workflow_rules','integration_plugins','notifications'] loop
  execute format('create policy %I on public.%I using (restaurant_id = public.my_restaurant_id())', 'tenant isolation ' || t, t);
end loop;
foreach t in array array['approval_settings','contacts'] loop
  execute format('create policy %I on public.%I using (exists (select 1 from public.companies c where c.id = %I.company_id and c.restaurant_id = public.my_restaurant_id()))',
    'tenant isolation ' || t, t, t);
end loop;
if 'email_settings' = any(l) then
  create policy "tenant isolation email_settings" on public.email_settings
    using (restaurant_id in (select users.restaurant_id from public.users where users.id = auth.uid()));
end if;
if (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l) and cmd = 'ALL') <> cardinality(l)
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> cardinality(l) then
  raise exception '0034-rollback achteraf: controle mislukt'; end if;
end $m$;
commit;
