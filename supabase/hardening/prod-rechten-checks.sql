-- POLDER controle 0036, ALLEEN LEZEN. Voor: voor 0036|34|25|t|0. Na: na 0036|0|0|f|0. De drie md5's: voor = na.
begin;
select case f when '469416b6636280c00f84839ce260ce38' then 'voor 0036' when 'afd46a8208fb2d9892202d4ce71b912e' then 'na 0036'
 else 'ONBEKEND' end stand,
 (select count(*) from pg_class c, unnest('{SELECT,INSERT,UPDATE,DELETE}'::text[]) o
 where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname not like '\_%'
 and (case o when 'DELETE' then has_table_privilege('authenticated', c.oid, o)
 else has_any_column_privilege('authenticated', c.oid, o) end) <> exists (select 1 from pg_policies p
 where p.schemaname = 'public' and p.tablename = c.relname and p.cmd in (o, 'ALL') and p.roles && '{authenticated,public}')) lint,
 (select count(*) from pg_class c, aclexplode(c.relacl) x where c.relnamespace = 'public'::regnamespace
 and x.grantee = 'authenticated'::regrole and x.privilege_type = 'MAINTAIN') maint,
 has_sequence_privilege('authenticated', 'public.platform_log_id_seq', 'USAGE') seq,
 (select count(*) from pg_class c, aclexplode(c.relacl) x where c.relnamespace = 'public'::regnamespace
 and x.grantee = 'anon'::regrole) anon,
 (select md5(string_agg(c.relname || x.privilege_type, '|' order by c.relname || x.privilege_type)) from pg_class c,
 aclexplode(c.relacl) x where c.relnamespace = 'public'::regnamespace and x.grantee = 'service_role'::regrole) service_md5,
 (select md5(string_agg(d.defaclacl::text, '|' order by d.defaclacl::text)) from pg_default_acl d
 where d.defaclrole::regrole::text = 'supabase_admin') admin_md5,
 (select md5(string_agg(tablename || policyname || cmd || coalesce(qual, '') || coalesce(with_check, ''), '|'
 order by tablename || policyname)) from pg_policies where schemaname = 'public')
 || (select md5(string_agg(proname || md5(prosrc) || coalesce(proacl::text, ''), '|' order by proname || md5(prosrc)))
 from pg_proc where pronamespace = 'public'::regnamespace) overige_md5,
 f vingerafdruk
from (select md5(string_agg(r, '|' order by r collate "C")) from (
select c.relname || ':' || x.grantee::regrole || ':' || x.privilege_type r from pg_class c, aclexplode(c.relacl) x
where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','S') and c.relname not like '\_%'
and x.grantee::regrole::text in ('anon','authenticated','service_role')
union all
select c.relname || '.' || a.attname || ':' || x.grantee::regrole || ':' || x.privilege_type
from pg_class c, pg_attribute a, aclexplode(a.attacl) x
where a.attrelid = c.oid and c.relnamespace = 'public'::regnamespace and c.relname not like '\_%'
and x.grantee::regrole::text in ('anon','authenticated','service_role')
union all
select d.defaclrole::regrole || ':' || d.defaclobjtype::text || ':' || d.defaclnamespace::regnamespace || ':'
|| x.grantee::regrole || ':' || x.privilege_type from pg_default_acl d, aclexplode(d.defaclacl) x
where d.defaclnamespace in (0, 'public'::regnamespace)) s) v(f);
rollback;
