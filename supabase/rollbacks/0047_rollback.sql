-- 0047 rollback (14c): bon_ondertekenen verwijderen. Na het terugdraaien van 0048 (geen recht meer).
begin;
do $m$ begin if (select proacl::text from pg_proc where oid = to_regprocedure('public.bon_ondertekenen(uuid,text,text,text)'))
  is distinct from '{postgres=X/postgres}' then raise exception '0047 rollback vooraf: stand wijkt af, niets gewijzigd'; end if; end $m$;
drop function public.bon_ondertekenen(uuid,text,text,text);
do $m$ begin if to_regprocedure('public.bon_ondertekenen(uuid,text,text,text)') is not null
then raise exception '0047 rollback achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
