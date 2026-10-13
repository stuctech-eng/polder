-- 0031 rolrechten facturen (hardening stap 10, architecture 13.22). Na 0030. Rollback: rollbacks/0031_rollback.sql
-- lezen VIEW_REVENUE (documents: MANAGE_INVOICES), schrijven MANAGE_INVOICES, nooit wissen; betalingen nooit wijzigen.
begin;
do $m$
declare t text; r text := 'restaurant_id = public.my_restaurant_id()'; k text;
  l text[] := array['invoices','invoice_lines','payments','documents'];
begin
if to_regprocedure('public.module_wacht()') is null
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 4
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l) and cmd = 'ALL'
      and policyname = 'tenant isolation ' || tablename) <> 4
then raise exception '0031 vooraf: uitgangsstand wijkt af, niets gewijzigd'; end if;

foreach t in array l loop execute format('drop policy %I on public.%I', 'tenant isolation ' || t, t); end loop;

execute format('create policy "invoices select" on public.invoices for select to authenticated using (%s and public.has_perm(''VIEW_REVENUE''))', r);
execute format('create policy "invoices insert" on public.invoices for insert to authenticated with check (%s and public.has_perm(''MANAGE_INVOICES'') and status = ''draft'')', r);
execute format('create policy "invoices update" on public.invoices for update to authenticated using (%1$s and public.has_perm(''MANAGE_INVOICES'')) with check (%1$s and public.has_perm(''MANAGE_INVOICES''))', r);
execute format('create policy "documents select" on public.documents for select to authenticated using (%s and public.has_perm(''MANAGE_INVOICES''))', r);
execute format('create policy "documents insert" on public.documents for insert to authenticated with check (%s and public.has_perm(''MANAGE_INVOICES''))', r);

foreach t in array array['invoice_lines','payments'] loop
  k := format('exists (select 1 from public.invoices i where i.id = %I.invoice_id and i.%s)', t, r);
  execute format('create policy %I on public.%I for select to authenticated using (%s and public.has_perm(''VIEW_REVENUE''))', t || ' select', t, k);
  k := k || ' and public.has_perm(''MANAGE_INVOICES'')';
  execute format('create policy %I on public.%I for insert to authenticated with check (%s)', t || ' insert', t, k);
  continue when t = 'payments';
  execute format('create policy "invoice_lines update" on public.invoice_lines for update to authenticated using (%1$s) with check (%1$s)', k);
  execute format('create policy "invoice_lines delete" on public.invoice_lines for delete to authenticated using (%s)', k);
end loop;

if (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 11
  or exists (select 1 from pg_policies where schemaname = 'public' and tablename = any(l) and cmd = 'ALL')
then raise exception '0031 achteraf: controle mislukt, niets gewijzigd'; end if;
end $m$;
commit;
