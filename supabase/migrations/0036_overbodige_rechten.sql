-- 0036 overbodige rechten (stap 13, arch. 13.25). Na 0035. Rollback: rollbacks/0036_rollback.sql
-- authenticated: rechten zonder policy, MAINTAIN, platform_log_id_seq eraf. Standaardrechten postgres (nieuwe tabellen):
-- MAINTAIN eraf voor anon/authenticated. Rest ongemoeid. Vooraf/achteraf exact gemeten stand.
begin;
do $m$
declare f text; v text := $v$select md5(string_agg(r, '|' order by r collate "C")) from (
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
where d.defaclnamespace in (0, 'public'::regnamespace)) s$v$;
begin
execute v into f;
if f is distinct from '469416b6636280c00f84839ce260ce38' then raise exception '0036 vooraf: stand wijkt af (%), niets gewijzigd', f; end if;
revoke delete, maintain on public.approval_settings, public.approvals, public.companies, public.configurations,
 public.invoices, public.workflow_rules from authenticated;
revoke update, delete, maintain on public.company_codes, public.cost_centers, public.daily_closings, public.departments,
 public.documents, public.payments, public.projects, public.receipt_lines from authenticated;
revoke all on public.contacts, public.integration_plugins, public.notifications from authenticated;
revoke maintain on public.activity_log, public.audit_log, public.domain_events, public.invoice_lines, public.open_tabs,
 public.receipts, public.restaurants, public.users from authenticated;
revoke all on sequence public.platform_log_id_seq from authenticated;
alter default privileges for role postgres in schema public revoke maintain on tables from anon, authenticated;
execute v into f;
if f is distinct from 'afd46a8208fb2d9892202d4ce71b912e' or exists (select 1 from pg_class c, unnest('{SELECT,INSERT,UPDATE,DELETE}'::text[]) o
where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname not like '\_%'
and (case o when 'DELETE' then has_table_privilege('authenticated', c.oid, o)
else has_any_column_privilege('authenticated', c.oid, o) end) <> exists (select 1 from pg_policies p
where p.schemaname = 'public' and p.tablename = c.relname and p.cmd in (o, 'ALL') and p.roles && '{authenticated,public}')
) then raise exception '0036 achteraf: mislukt (%), niets gewijzigd', f; end if;
end $m$;
commit;
