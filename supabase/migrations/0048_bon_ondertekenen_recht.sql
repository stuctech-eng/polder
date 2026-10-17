-- 0048 handtekening (14c, 6/6): PNG-controle (png_geldig, gebruikt door bon_ondertekenen) en daarna het recht op bon_ondertekenen voor
-- ingelogde gebruikers (de functie controleert zelf rol en restaurant); nacontrole van bon_ondertekenen. Na 0047. Rollback: rollbacks/0048_rollback.sql
begin;
do $m$ begin if (select count(*) from pg_proc where oid = to_regproc('public.bon_ondertekenen') and proacl::text = '{postgres=X/postgres}') <> 1
  or to_regproc('public.png_geldig') is not null then raise exception '0048 vooraf: stand wijkt af, niets gewijzigd'; end if; end $m$;

-- echte PNG: geldige base64, PNG-handtekening, eerst IHDR (breedte 1-2048, hoogte 1-1024), eindigt op IEND; data-URL 100-200000 tekens
create function public.png_geldig(p text) returns boolean language plpgsql immutable set search_path = public, pg_temp as $f$
declare b bytea;
begin
  if p is null or length(p) not between 100 and 200000 or left(p, 22) <> 'data:image/png;base64,'
     or substr(p, 23) !~ '^[A-Za-z0-9+/]+={0,2}$' then return false; end if;
  b := decode(substr(p, 23), 'base64');
  return substr(b, 1, 16) = '\x89504e470d0a1a0a0000000d49484452'::bytea and substr(b, length(b) - 11) = '\x0000000049454e44ae426082'::bytea
    and get_byte(b, 16) = 0 and get_byte(b, 17) = 0 and get_byte(b, 18) * 256 + get_byte(b, 19) between 1 and 2048
    and get_byte(b, 20) = 0 and get_byte(b, 21) = 0 and get_byte(b, 22) * 256 + get_byte(b, 23) between 1 and 1024;
exception when others then return false;
end $f$;
revoke all on function public.png_geldig(text) from public, anon, authenticated, service_role;

grant execute on function public.bon_ondertekenen(uuid,text,text,text) to authenticated;

do $m$ begin if (select count(*) from pg_proc where oid = to_regproc('public.bon_ondertekenen') and prosecdef and pg_get_userbyid(proowner) = 'postgres'
  and proconfig = '{"search_path=public, pg_temp"}' and proacl::text = '{postgres=X/postgres,authenticated=X/postgres}') <> 1
  or (select count(*) from pg_proc where oid = to_regproc('public.png_geldig') and not prosecdef and proacl::text = '{postgres=X/postgres}'
      and pg_get_userbyid(proowner) = 'postgres' and proconfig = '{"search_path=public, pg_temp"}') <> 1
  or not public.png_geldig('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNgAAAAAgABSK+kcQAAAABJRU5ErkJggg==')
  or public.png_geldig('data:image/png;base64,' || repeat('A', 200))
  or (select string_agg(proname || ':' || prosecdef, ',' order by proname) from pg_proc where prosrc like '%polder.ondertekening%')
  <> 'approvals_guard:false,bon_ondertekenen:true,receipts_guard:false,teken_wacht:false'
then raise exception '0048 achteraf: controle mislukt, niets gewijzigd'; end if; end $m$;
commit;
