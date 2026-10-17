-- 0048 rollback (14c): recht op bon_ondertekenen weer intrekken en png_geldig verwijderen. Daarna kan niemand de functie aanroepen.
begin;
do $m$ begin if (select proacl::text from pg_proc where oid = to_regprocedure('public.bon_ondertekenen(uuid,text,text,text)'))
  is distinct from '{postgres=X/postgres,authenticated=X/postgres}' or to_regproc('public.png_geldig') is null
then raise exception '0048 rollback vooraf: stand wijkt af, niets gewijzigd'; end if; end $m$;
revoke execute on function public.bon_ondertekenen(uuid,text,text,text) from authenticated;
drop function public.png_geldig(text);
do $m$ begin if (select proacl::text from pg_proc where oid = 'public.bon_ondertekenen(uuid,text,text,text)'::regprocedure) <> '{postgres=X/postgres}'
  or to_regproc('public.png_geldig') is not null
then raise exception '0048 rollback achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
