-- Rollback 0024: de 15 policies terug naar de tekst van 0003/0006. Alleen als ALLE 15 exact in de 0024-stand staan; anders afbreken, niets gewijzigd.
do $m$
declare
l text[]:=array['companies','invoices','documents','workflow_rules','configurations','notifications','integration_plugins',
'contacts:c','departments:c','cost_centers:c','projects:c','company_codes:c','approval_settings:c','invoice_lines:i','payments:i'];
e text; t text; o text; f text; a text; oud text; nw text; nu text; n int; r int; err text:='';
begin
perform set_config('quote_all_identifiers','off',true); perform set_config('lock_timeout','5s',true);
for r in 1..2 loop
perform set_config('search_path','',true);
foreach e in array l loop
t:=split_part(e,':',1); a:=split_part(e,':',2);
o:=case a when 'c' then 'companies' else 'invoices' end; f:=case a when 'c' then 'company_id' else 'invoice_id' end;
if a='' then
oud:='(restaurant_id IN ( SELECT users.restaurant_id FROM public.users WHERE (users.id = auth.uid())))';
nw:='(restaurant_id = public.my_restaurant_id())';
else
oud:=format('(%s IN ( SELECT %s.id FROM public.%s %s WHERE (%s.restaurant_id IN ( SELECT users.restaurant_id FROM public.users WHERE (users.id = auth.uid())))))',f,a,o,a,a);
nw:=format('(EXISTS ( SELECT 1 FROM public.%s %s WHERE ((%s.id = %s.%s) AND (%s.restaurant_id = public.my_restaurant_id()))))',o,a,a,t,f,a);
end if;
select count(*) into n from pg_policy where polrelid=to_regclass('public.'||t);
nu:=null;
select regexp_replace(pg_get_expr(p.polqual,p.polrelid),'\s+',' ','g') into nu from pg_policy p join pg_class c on c.oid=p.polrelid
where c.oid=to_regclass('public.'||t) and p.polname='tenant isolation '||t and c.relrowsecurity
and p.polcmd='*' and p.polroles='{0}' and p.polpermissive and p.polwithcheck is null;
if n<>1 or nu is null or nu<>(case r when 1 then nw else oud end) then err:=err||t||'; '; end if;
end loop;
if err<>'' then raise exception '0024-rollback %: niet alle 15 in de verwachte stand, niets teruggedraaid. Afwijkend: %',
  case r when 1 then 'vooraf' else 'achteraf' end, err; end if;
exit when r=2;
perform set_config('search_path','public, pg_temp',true);
foreach e in array l loop
t:=split_part(e,':',1); a:=split_part(e,':',2);
o:=case a when 'c' then 'companies' else 'invoices' end; f:=case a when 'c' then 'company_id' else 'invoice_id' end;
execute format('alter policy %I on public.%I using (%s)','tenant isolation '||t,t,case when a='' then
'restaurant_id in (select restaurant_id from users where users.id = auth.uid())'
else format('%s in (select %s.id from %s %s where %s.restaurant_id in (select restaurant_id from users where users.id = auth.uid()))',f,a,o,a,a) end);
end loop;
end loop;
end $m$;
