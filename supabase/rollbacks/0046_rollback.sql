-- 0046 rollback (14c): teken_wacht en de twee triggers verwijderen. Na het terugdraaien van 0047.
begin;
do $m$ begin if to_regprocedure('public.teken_wacht()') is null or to_regprocedure('public.bon_ondertekenen(uuid,text,text,text)') is not null
  or (select count(*) from pg_trigger where tgname like '%teken\_wacht') <> 2
then raise exception '0046 rollback vooraf: stand wijkt af, niets gewijzigd'; end if; end $m$;
drop trigger receipts_teken_wacht on public.receipts;
drop trigger approvals_teken_wacht on public.approvals;
drop function public.teken_wacht();
do $m$ begin if exists (select 1 from pg_trigger where tgname like '%teken\_wacht') or to_regprocedure('public.teken_wacht()') is not null
then raise exception '0046 rollback achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
