-- Rollback 0031 rolrechten facturen. NOODMAATREGEL: zet de oude policies terug ("alleen eigen restaurant"), en daarmee
-- ook het oude lek (elke rol mag facturen en betalingen wijzigen en wissen). Alleen tijdelijk gebruiken. Eerst 0032 terugdraaien.
begin;
do $m$
declare t text; l text[] := array['invoices','invoice_lines','payments','documents'];
begin
if to_regprocedure('public.invoices_guard()') is not null
  or (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 11
  or exists (select 1 from pg_policies where schemaname = 'public' and tablename = any(l) and cmd = 'ALL') then
  raise exception '0031-rollback vooraf: 0032 nog aanwezig of 0031 niet (volledig) aanwezig, niets gewijzigd'; end if;
foreach t in array l loop
  execute (select string_agg(format('drop policy %I on public.%I;', policyname, t), ' ') from pg_policies where schemaname = 'public' and tablename = t);
end loop;
create policy "tenant isolation invoices" on public.invoices using (restaurant_id = public.my_restaurant_id());
create policy "tenant isolation documents" on public.documents using (restaurant_id = public.my_restaurant_id());
create policy "tenant isolation invoice_lines" on public.invoice_lines
  using (exists (select 1 from public.invoices i where i.id = invoice_lines.invoice_id and i.restaurant_id = public.my_restaurant_id()));
create policy "tenant isolation payments" on public.payments
  using (exists (select 1 from public.invoices i where i.id = payments.invoice_id and i.restaurant_id = public.my_restaurant_id()));
if (select count(*) from pg_policies where schemaname = 'public' and tablename = any(l)) <> 4 then
  raise exception '0031-rollback achteraf: controle mislukt'; end if;
end $m$;
commit;
