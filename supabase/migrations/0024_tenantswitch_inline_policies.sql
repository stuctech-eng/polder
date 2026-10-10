-- 0024 tenantswitch (zie docs/architecture.md 13.17): één transactie, controle vooraf en achteraf.
do $m$
declare
l text[]:=array['companies','invoices','documents','workflow_rules','configurations','notifications','integration_plugins',
'contacts:c','departments:c','cost_centers:c','projects:c','company_codes:c','approval_settings:c','invoice_lines:i','payments:i'];
e text; t text; o text; f text; a text; oud text; nw text; nu text; n int; r int; err text:=''; vo int:=0; vn int:=0;
begin
perform set_config('search_path','',true); perform set_config('quote_all_identifiers','off',true); perform set_config('lock_timeout','5s',true);
if not coalesce((select prosecdef from pg_proc where oid=to_regprocedure('public.my_restaurant_id()')),false) then
raise exception '0024: my_restaurant_id() ontbreekt'; end if;
for r in 1..2 loop
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
if n<>1 or nu is null then err:=err||t||': policy/vorm/RLS afwijkend; ';
elsif r=1 and nu=oud then vo:=vo+1;
elsif nu=nw then vn:=vn+1;
else err:=err||t||': onbekende tekst '||quote_literal(nu)||'; ';
end if;
end loop;
if r=2 then
if err<>'' or vn<>15 then raise exception '0024 achteraf (niets gewijzigd): %',err; end if;
else
if err<>'' then raise exception '0024 vooraf: %',err; end if;
if vn=15 then raise exception '0024 is al uitgevoerd'; end if;
if vo<>15 then raise exception '0024 vooraf: gemengde stand (% oud, % nieuw)',vo,vn; end if;
vn:=0;
foreach e in array l loop
t:=split_part(e,':',1); a:=split_part(e,':',2);
o:=case a when 'c' then 'companies' else 'invoices' end; f:=case a when 'c' then 'company_id' else 'invoice_id' end;
execute format('alter policy %I on public.%I using (%s)','tenant isolation '||t,t,case when a='' then 'restaurant_id = public.my_restaurant_id()'
else format('exists (select 1 from public.%s %s where %s.id = %s.%s and %s.restaurant_id = public.my_restaurant_id())',o,a,a,t,f,a) end);
end loop;
end if;
end loop;
end $m$;
