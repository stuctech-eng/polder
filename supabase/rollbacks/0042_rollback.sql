-- Rollback 0042 (wacht op de bon). NOODMAATREGEL.
-- Daarna kan een PIN-bon weer ZONDER PIN worden goedgekeurd (oude lek). De oude app werkt dan weer.
-- Verwijdert precies de objecten van 0042, niets anders.
begin;
do $m$ begin
if not (exists (select 1 from pg_trigger where tgname = 'receipts_pin_wacht') and to_regprocedure('public.receipts_pin_wacht()') is not null)
then raise exception '0042-rollback vooraf: 0042 niet (precies) aanwezig, niets gewijzigd'; end if; end $m$;
drop trigger receipts_pin_wacht on public.receipts;
drop function public.receipts_pin_wacht();
do $m$ begin
if exists (select 1 from pg_trigger where tgname = 'receipts_pin_wacht') or to_regprocedure('public.receipts_pin_wacht()') is not null then raise exception '0042-rollback achteraf: controle mislukt'; end if; end $m$;
commit;
