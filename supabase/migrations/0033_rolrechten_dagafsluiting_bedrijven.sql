-- 0033 rolrechten dagafsluiting en bedrijfsgegevens (hardening stap 11, architecture 13.23). Na 0032. Rollback: rollbacks/0033_rollback.sql
-- dagafsluiting: lezen VIEW_DAILY_CLOSING, aanmaken EXECUTE_DAILY_CLOSING op eigen naam; bedrijven: lezen iedereen, schrijven MANAGE_COMPANIES; nooit wissen.
begin;
do $m$
declare t text; r text := 'restaurant_id = public.my_restaurant_id()'; k text;
  l text[] := array['daily_closings','companies','departments','cost_centers','projects','company_codes'];
begin
if to_regprocedure('public.invoices_guard()') is null
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 6
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l) and cmd = 'ALL'
      and policyname = 'tenant isolation ' || tablename) <> 6
then raise exception '0033 vooraf: uitgangsstand wijkt af, niets gewijzigd'; end if;

foreach t in array l loop execute format('drop policy %I on public.%I', 'tenant isolation ' || t, t); end loop;

execute format('create policy "daily_closings select" on public.daily_closings for select to authenticated using (%s and public.has_perm(''VIEW_DAILY_CLOSING''))', r);
execute format('create policy "daily_closings insert" on public.daily_closings for insert to authenticated with check (%s and public.has_perm(''EXECUTE_DAILY_CLOSING'') and closed_by = auth.uid())', r);
execute format('create policy "companies select" on public.companies for select to authenticated using (%s)', r);
execute format('create policy "companies insert" on public.companies for insert to authenticated with check (%s and public.has_perm(''MANAGE_COMPANIES''))', r);
execute format('create policy "companies update" on public.companies for update to authenticated using (%1$s and public.has_perm(''MANAGE_COMPANIES'')) with check (%1$s and public.has_perm(''MANAGE_COMPANIES''))', r);

foreach t in array l[3:6] loop
  k := format('exists (select 1 from public.companies c where c.id = %I.company_id and c.%s)', t, r);
  execute format('create policy %I on public.%I for select to authenticated using (%s)', t || ' select', t, k);
  execute format('create policy %I on public.%I for insert to authenticated with check (%s and public.has_perm(''MANAGE_COMPANIES''))', t || ' insert', t, k);
end loop;

if (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 13
  or exists (select 1 from pg_policies where schemaname = 'public' and tablename = any(l) and (cmd = 'ALL' or roles <> '{authenticated}'))
then raise exception '0033 achteraf: controle mislukt, niets gewijzigd'; end if;
end $m$;
commit;
