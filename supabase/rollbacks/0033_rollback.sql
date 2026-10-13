-- Rollback 0033 rolrechten dagafsluiting en bedrijfsgegevens. NOODMAATREGEL: zet de oude policies terug ("alleen eigen restaurant"),
-- en daarmee ook het oude lek (elke rol mag dagafsluitingen en bedrijven wijzigen en wissen). Alleen tijdelijk. Eerst 0034 terugdraaien.
begin;
do $m$
declare t text; l text[] := array['daily_closings','companies','departments','cost_centers','projects','company_codes'];
begin
if exists (select 1 from pg_policies where schemaname = 'public' and policyname = 'configurations select')
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 13
  or exists (select 1 from pg_policies where schemaname = 'public' and tablename = any(l) and cmd = 'ALL') then
  raise exception '0033-rollback vooraf: 0034 nog aanwezig of 0033 niet (volledig) aanwezig, niets gewijzigd'; end if;
foreach t in array l loop
  execute (select string_agg(format('drop policy %I on public.%I;', policyname, t), ' ') from pg_policies where schemaname = 'public' and tablename = t);
end loop;
foreach t in array l[1:2] loop
  execute format('create policy %I on public.%I using (restaurant_id = public.my_restaurant_id())', 'tenant isolation ' || t, t);
end loop;
foreach t in array l[3:6] loop
  execute format('create policy %I on public.%I using (exists (select 1 from public.companies c where c.id = %I.company_id and c.restaurant_id = public.my_restaurant_id()))',
    'tenant isolation ' || t, t, t);
end loop;
if (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l) and cmd = 'ALL') <> 6
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 6 then
  raise exception '0033-rollback achteraf: controle mislukt'; end if;
end $m$;
commit;
