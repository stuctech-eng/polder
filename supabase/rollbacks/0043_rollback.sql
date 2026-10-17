-- 0043 rollback (14c): module signature en bon_vingerafdruk verwijderen. Na het terugdraaien van 0044.
-- Weigert als er al iets met handtekening is (instelling, regel of module-instelling per restaurant): eerst beoordelen.
begin;
do $m$ begin if to_regprocedure('public.bon_vingerafdruk(uuid)') is null or not exists (select 1 from public.features where key = 'signature')
  or position('polder.ondertekening' in pg_get_functiondef('public.receipts_guard()'::regprocedure)) > 0
  or exists (select 1 from public.restaurant_features where feature = 'signature')
  or exists (select 1 from public.approval_settings where method = 'signature') or exists (select 1 from public.approvals where method = 'signature')
then raise exception '0043 rollback vooraf: stand wijkt af, niets gewijzigd'; end if; end $m$;
drop function public.bon_vingerafdruk(uuid);
delete from public.features where key = 'signature';
do $m$ begin if to_regprocedure('public.bon_vingerafdruk(uuid)') is not null or exists (select 1 from public.features where key = 'signature')
then raise exception '0043 rollback achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
