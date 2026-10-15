-- POLDER - rechteninventaris (stap 13a). ALLEEN LEZEN, eindigt met rollback. Basis voor migratie 0036.
-- Per tabel/sequence: eigenaar, RLS, rechten (aclexplode, ook MAINTAIN) van anon/authenticated/service_role, kolom-SELECT,
-- policies. Plus standaardrechten per rol, functie-eigenaren, versie. volledig_leesbaar 'nee' = geen bewijs van afwezigheid.
begin;
with t as (select c.oid, c.relname, c.relkind, c.relrowsecurity, pg_get_userbyid(c.relowner) eig from pg_class c
           where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','S') and c.relname not like '\_%'),
     a as (select t.oid, g.rolname, string_agg(x.privilege_type, ',' order by x.privilege_type) p
           from t cross join lateral aclexplode(coalesce((select relacl from pg_class where oid = t.oid), '{}')) x
           join pg_roles g on g.oid = x.grantee where g.rolname in ('anon','authenticated','service_role') group by 1, 2),
     k as (select table_name, count(*) n from information_schema.column_privileges
           where table_schema = 'public' and grantee = 'authenticated' and privilege_type = 'SELECT' group by 1),
     p as (select tablename, string_agg(cmd || ':' || array_to_string(roles, '+'), ' ' order by cmd) o from pg_policies
           where schemaname = 'public' group by 1)
select 1 v, case t.relkind when 'S' then 'sequence' else 'tabel' end soort, t.relname naam, t.eig eigenaar,
       t.relrowsecurity::text rls,
       coalesce((select a.p from a where a.oid = t.oid and a.rolname = 'authenticated'), '-') authenticated,
       coalesce((select a.p from a where a.oid = t.oid and a.rolname = 'anon'), '-') anon,
       coalesce((select a.p from a where a.oid = t.oid and a.rolname = 'service_role'), '-') service_role,
       coalesce(k.n::text, '0') auth_kolom_select, coalesce(p.o, '-') policies,
       case when pg_has_role(current_user, t.eig, 'USAGE') then 'ja' else 'nee' end volledig_leesbaar
from t left join k on k.table_name = t.relname left join p on p.tablename = t.relname
union all
select 2, 'standaardrecht', d.defaclobjtype::text, pg_get_userbyid(d.defaclrole), coalesce(d.defaclnamespace::regnamespace::text, 'alle'),
       array_to_string(d.defaclacl, ' '), '', '', '', '', 'ja'
from pg_default_acl d where d.defaclnamespace in (0, 'public'::regnamespace)
union all
select 3, 'functie-eigenaar', pg_get_userbyid(f.proowner), count(*)::text, '', '', '', '', '', '',
       case when pg_has_role(current_user, f.proowner, 'USAGE') then 'ja' else 'nee' end
from pg_proc f where f.pronamespace = 'public'::regnamespace group by f.proowner
union all
select 4, 'versie', current_setting('server_version'), current_user, '', '', '', '', '', '',
       case when bool_and(pg_has_role(current_user, c.relowner, 'USAGE')) then 'ja, alle objecten' else 'NEE: zie regels met nee' end
from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','S')
order by 1, 2, 3;
rollback;
