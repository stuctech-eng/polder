-- Rollback 0032 factuurwacht. NOODMAATREGEL: haalt de statusregels voor facturen weg (oude, zwakkere stand). 0031 blijft staan.
begin;
do $m$ begin
if to_regprocedure('public.invoices_guard()') is null or to_regprocedure('public.invoice_child_guard()') is null
  or (select count(*) from pg_trigger where tgname in ('invoices_guard','invoice_child_guard')) <> 3 then
  raise exception '0032-rollback vooraf: 0032 niet (volledig) aanwezig, niets gewijzigd'; end if; end $m$;
drop trigger invoices_guard on public.invoices;
drop trigger invoice_child_guard on public.invoice_lines;
drop trigger invoice_child_guard on public.payments;
drop function public.invoices_guard();
drop function public.invoice_child_guard();
commit;
